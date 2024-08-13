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
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.CheckpointStates
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

    persist_store(store)
  end

  @spec on_block(BlockInfo.t()) :: :ok | {:error, String.t()}
  def on_block(%BlockInfo{} = block_info) do
    store = fetch_store!()
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

        %Store{finalized_checkpoint: new_finalized_checkpoint} = new_store

        prune_old_states(last_finalized_checkpoint.epoch, new_finalized_checkpoint.epoch)

        persist_store(new_store)

      {:error, reason} ->
        Logger.error("[Fork choice] Failed to add block: #{reason}", slot: slot, root: block_root)
        {:error, reason}
    end
  end

  @spec on_attestation(Types.Attestation.t()) :: :ok
  def on_attestation(%Attestation{} = attestation) do
    state = fetch_store!()
    id = attestation.signature |> Base.encode16() |> String.slice(0, 8)
    Logger.debug("[Fork choice] Adding attestation #{id} to the store")

    state =
      case Handlers.on_attestation(state, attestation, false) do
        {:ok, new_state} -> new_state
        _ -> state
      end

    persist_store(state)
  end

  @spec on_attester_slashing(Types.AttesterSlashing.t()) :: :ok
  def on_attester_slashing(attester_slashing) do
    Logger.info("[Fork choice] Adding attester slashing to the store")
    state = fetch_store!()

    case Handlers.on_attester_slashing(state, attester_slashing) do
      {:ok, new_state} ->
        persist_store(new_state)

      _ ->
        Logger.error("[Fork choice] Failed to add attester slashing to the store")
    end
  end

  @spec on_tick(Types.uint64()) :: :ok
  def on_tick(time) do
    store = fetch_store!()
    %Store{finalized_checkpoint: last_finalized_checkpoint} = store

    new_store = Handlers.on_tick(store, time)
    %Store{finalized_checkpoint: new_finalized_checkpoint} = new_store
    prune_old_states(last_finalized_checkpoint.epoch, new_finalized_checkpoint.epoch)
    persist_store(new_store)
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

  defp prune_old_states(last_finalized_epoch, new_finalized_epoch) do
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

    # Prefetch relevant states.
    states =
      Metrics.span_operation(:prefetch_states, nil, nil, fn ->
        attestations
        |> Enum.map(& &1.data.target)
        |> Enum.uniq()
        |> Enum.flat_map(&fetch_checkpoint_state/1)
        |> Map.new()
      end)

    # Prefetch committees for all relevant epochs.
    Metrics.span_operation(:prefetch_committees, nil, nil, fn ->
      Enum.each(states, fn {ch, state} -> Accessors.maybe_prefetch_committees(state, ch.epoch) end)
    end)

    with {:ok, new_store} <- apply_on_block(store, block_info),
         {:ok, new_store} <- process_attestations(new_store, attestations, states),
         {:ok, new_store} <- process_attester_slashings(new_store, attester_slashings) do
      {:ok, new_store}
    end
  end

  def fetch_checkpoint_state(checkpoint) do
    case CheckpointStates.get_checkpoint_state(checkpoint) do
      {:ok, state} -> [{checkpoint, state}]
      _other -> []
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

  defp process_attestations(store, attestations, states) do
    Metrics.span_operation(:attestations, nil, nil, fn ->
      apply_handler(
        attestations,
        store,
        &Handlers.on_attestation(&1, &2, true, states)
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

  defp persist_store(store) do
    StoreDb.persist_store(store)
    Logger.debug("[Fork choice] Store persisted")
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

    persist_store(new_store)
  end
end
