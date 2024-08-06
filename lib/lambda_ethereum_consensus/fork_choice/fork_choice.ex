defmodule LambdaEthereumConsensus.ForkChoice do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  require Logger
  alias LambdaEthereumConsensus.Execution.ExecutionChain
  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.ForkChoice.Head
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.StateDb
  alias LambdaEthereumConsensus.Store.StoreDb
  alias Types.Attestation
  alias Types.BlockInfo
  alias Types.Checkpoint
  alias Types.Store

  ##########################
  ### Public API
  ##########################

  @spec init_store(Store.t(), Types.uint64()) :: :ok | :error
  def init_store(%Store{head_slot: head_slot, head_root: head_root} = store, time) do
    Logger.info("[Fork choice] Initialized store.", slot: head_slot)

    store = Handlers.on_tick(store, time)

    :telemetry.execute([:sync, :store], %{slot: Store.get_current_slot(store)})
    :telemetry.execute([:sync, :on_block], %{slot: head_slot})

    Metrics.block_status(head_root, head_slot, :transitioned)

    StoreDb.persist_store(store)
  end

  @spec on_block(Store.t(), BlockInfo.t()) :: :ok | {:error, String.t()}
  def on_block(store, %BlockInfo{} = block_info) do
    slot = block_info.signed_block.message.slot
    block_root = block_info.root

    Logger.info("[Fork choice] Adding new block", root: block_info.root, slot: slot)

    %Store{finalized_checkpoint: last_finalized_checkpoint} = store

    result =
      :telemetry.span([:sync, :on_block], %{}, fn ->
        {process_block(block_info, store), %{}}
      end)

    case result do
      {:ok, new_store} ->
        :telemetry.execute([:sync, :on_block], %{slot: slot})
        Logger.info("[Fork choice] Added new block", slot: slot, root: block_root)

        :telemetry.span([:fork_choice, :recompute_head], %{}, fn ->
          {recompute_head(new_store), %{}}
        end)

        new_store
        |> prune_old_states(last_finalized_checkpoint.epoch)
        |> tap(&Store.persist/1)

      {:error, reason} ->
        Logger.error("[Fork choice] Failed to add block: #{reason}", slot: slot, root: block_root)
        {:error, reason}
    end
  end

  @spec on_attestation(Store.t(), Types.Attestation.t()) :: Store.t()
  def on_attestation(store, %Attestation{} = attestation) do
    id = attestation.signature |> Base.encode16() |> String.slice(0, 8)
    Logger.debug("[Fork choice] Adding attestation #{id} to the store")

    store =
      case Handlers.on_attestation(store, attestation, false) do
        {:ok, new_store} -> new_store
        _ -> store
      end

    tap(store, &StoreDb.persist_store/1)
  end

  @spec on_attester_slashing(Store.t(), Types.AttesterSlashing.t()) :: Store.t()
  def on_attester_slashing(store, attester_slashing) do
    Logger.info("[Fork choice] Adding attester slashing to the store")

    case Handlers.on_attester_slashing(store, attester_slashing) do
      {:ok, new_store} ->
        tap(new_store, &StoreDb.persist_store/1)

      _ ->
        Logger.error("[Fork choice] Failed to add attester slashing to the store")
        store
    end
  end

  @spec on_tick(Store.t(), Types.uint64()) :: Store.t()
  def on_tick(store, time) do
    %Store{finalized_checkpoint: last_finalized_checkpoint} = store

    Handlers.on_tick(store, time)
    |> prune_old_states(last_finalized_checkpoint.epoch)
    |> tap(&StoreDb.persist_store/1)
  end

  @spec get_current_chain_slot() :: Types.slot()
  def get_current_chain_slot() do
    time = :os.system_time(:second)
    genesis_time = StoreDb.fetch_genesis_time!()
    compute_current_slot(time, genesis_time)
  end

  @spec get_finalized_checkpoint() :: Types.Checkpoint.t()
  def get_finalized_checkpoint() do
    %{finalized_checkpoint: finalized} = fetch_store!()
    finalized
  end

  @spec get_justified_checkpoint() :: Types.Checkpoint.t()
  def get_justified_checkpoint() do
    %{justified_checkpoint: justified} = fetch_store!()
    justified
  end

  @spec get_fork_digest() :: Types.fork_digest()
  def get_fork_digest() do
    get_current_chain_slot()
    |> compute_fork_digest(ChainSpec.get_genesis_validators_root())
  end

  @spec get_fork_digest_for_slot(Types.slot()) :: binary()
  def get_fork_digest_for_slot(slot) do
    compute_fork_digest(slot, ChainSpec.get_genesis_validators_root())
  end

  @spec get_fork_version() :: Types.version()
  def get_fork_version() do
    get_current_chain_slot()
    |> Misc.compute_epoch_at_slot()
    |> ChainSpec.get_fork_version_for_epoch()
  end

  @spec get_current_status_message() :: Types.StatusMessage.t()
  def get_current_status_message() do
    %{
      head_root: head_root,
      head_slot: head_slot,
      finalized_checkpoint: %{root: finalized_root, epoch: finalized_epoch}
    } = fetch_store!()

    %Types.StatusMessage{
      fork_digest: compute_fork_digest(head_slot, ChainSpec.get_genesis_validators_root()),
      finalized_root: finalized_root,
      finalized_epoch: finalized_epoch,
      head_root: head_root,
      head_slot: head_slot
    }
  end

  ##########################
  ### Private Functions
  ##########################

  defp prune_old_states(store, last_finalized_epoch) do
    new_finalized_epoch = store.finalized_checkpoint.epoch

    if last_finalized_epoch < new_finalized_epoch do
      new_finalized_slot =
        new_finalized_epoch * ChainSpec.get("SLOTS_PER_EPOCH")

      Task.Supervisor.start_child(
        PruneStatesSupervisor,
        fn -> StateDb.prune_states_older_than(new_finalized_slot) end
      )

      Task.Supervisor.start_child(
        PruneBlocksSupervisor,
        fn -> BlockDb.prune_blocks_older_than(new_finalized_slot) end
      )

      Task.Supervisor.start_child(
        PruneBlobsSupervisor,
        fn -> BlobDb.prune_old_blobs(new_finalized_slot) end
      )
    end

    Store.prune(store)
  end

  def apply_handler(iter, state, handler) do
    iter
    |> Enum.reduce_while({:ok, state}, fn
      x, {:ok, st} -> {:cont, handler.(st, x)}
      _, {:error, _} = err -> {:halt, err}
    end)
  end

  @spec process_block(BlockInfo.t(), Store.t()) :: Store.t()
  def process_block(%BlockInfo{signed_block: signed_block} = block_info, store) do
    attestations = signed_block.message.body.attestations
    attester_slashings = signed_block.message.body.attester_slashings

    with {:ok, new_store} <- apply_on_block(store, block_info),
         {:ok, new_store} <- process_attestations(new_store, attestations),
         {:ok, new_store} <- process_attester_slashings(new_store, attester_slashings) do
      {:ok, new_store}
    end
  end

  defp apply_on_block(store, block_info) do
    Metrics.span_operation(:on_block, nil, nil, fn -> Handlers.on_block(store, block_info) end)
  end

  defp process_attester_slashings(store, attester_slashings) do
    Metrics.span_operation(:attester_slashings, nil, nil, fn ->
      apply_handler(attester_slashings, store, &Handlers.on_attester_slashing/2)
    end)
  end

  defp process_attestations(store, attestations) do
    Metrics.span_operation(:attestations, nil, nil, fn ->
      apply_handler(
        attestations,
        store,
        &Handlers.on_attestation(&1, &2, true)
      )
    end)
  end

  @spec recompute_head(Store.t()) :: :ok
  def recompute_head(store) do
    {:ok, head_root} = Head.get_head(store)
    head_block = Blocks.get_block!(head_root)

    Handlers.notify_forkchoice_update(store, head_block)

    %{slot: slot, body: body} = head_block

    OperationsCollector.notify_new_block(head_block)
    Libp2pPort.notify_new_head(slot, head_root)
    ExecutionChain.notify_new_block(slot, body.eth1_data, body.execution_payload)

    update_fork_choice_data(
      head_root,
      slot,
      store.justified_checkpoint,
      store.finalized_checkpoint
    )

    Logger.debug("[Fork choice] Updated fork choice cache", slot: slot)

    :ok
  end

  defp fetch_store!() do
    {:ok, store} = StoreDb.fetch_store()
    store
  end

  defp compute_current_slot(time, genesis_time),
    do: div(time - genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))

  defp compute_fork_digest(slot, genesis_validators_root) do
    Misc.compute_epoch_at_slot(slot)
    |> ChainSpec.get_fork_version_for_epoch()
    |> Misc.compute_fork_digest(genesis_validators_root)
  end

  @spec update_fork_choice_data(Types.root(), Types.slot(), Checkpoint.t(), Checkpoint.t()) ::
          :ok
  defp update_fork_choice_data(head_root, head_slot, justified, finalized) do
    store = fetch_store!()

    new_store = %{
      store
      | head_root: head_root,
        head_slot: head_slot,
        justified_checkpoint: justified,
        finalized_checkpoint: finalized
    }

    StoreDb.persist_store(new_store)
  end
end
