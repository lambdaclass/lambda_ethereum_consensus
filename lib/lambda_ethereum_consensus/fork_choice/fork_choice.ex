defmodule LambdaEthereumConsensus.ForkChoice do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  require Logger

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Execution.ExecutionChain
  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.ForkChoice.Head
  alias LambdaEthereumConsensus.P2P.Gossip.OperationsCollector
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.StateDb
  alias LambdaEthereumConsensus.Store.StoreDb
  alias LambdaEthereumConsensus.Validator.ValidatorManager
  alias Types.Attestation
  alias Types.SignedBeaconBlock
  alias Types.Store

  ##########################
  ### Public API
  ##########################

  @spec init_store(Store.t(), Types.slot(), Types.uint64()) :: :ok | :error
  def init_store(%Store{} = store, head_slot, time) do
    Logger.info("[Fork choice] Initialized store.", slot: head_slot)

    store = Handlers.on_tick(store, time)

    :telemetry.execute([:sync, :store], %{slot: Store.get_current_slot(store)})
    :telemetry.execute([:sync, :on_block], %{slot: head_slot})

    persist_fork_choice_store(store)
  end

  @spec on_block(SignedBeaconBlock.t(), Types.root(), pid()) :: :ok | :error
  def on_block(%SignedBeaconBlock{} = signed_block, block_root, from \\ self()) do
    store = fetch_fork_choice_store!()
    slot = signed_block.message.slot

    Logger.info("[Fork choice] Adding new block", root: block_root, slot: slot)

    %Store{finalized_checkpoint: last_finalized_checkpoint} = store

    result =
      :telemetry.span([:sync, :on_block], %{}, fn ->
        {process_block(block_root, signed_block, store), %{}}
      end)

    case result do
      {:ok, new_store} ->
        :telemetry.execute([:sync, :on_block], %{slot: slot})
        Logger.info("[Fork choice] Added new block", slot: slot, root: block_root)

        Task.start_link(__MODULE__, :recompute_head, [new_store])

        %Store{finalized_checkpoint: new_finalized_checkpoint} = new_store

        prune_old_states(last_finalized_checkpoint.epoch, new_finalized_checkpoint.epoch)

        GenServer.cast(from, {:block_processed, block_root, true})
        persist_fork_choice_store(new_store)

      {:error, reason} ->
        Logger.error("[Fork choice] Failed to add block: #{reason}", slot: slot, root: block_root)
        GenServer.cast(from, {:block_processed, block_root, false})
    end
  end

  @spec on_attestation(Types.Attestation.t()) :: :ok
  def on_attestation(%Attestation{} = attestation) do
    state = fetch_fork_choice_store!()
    id = attestation.signature |> Base.encode16() |> String.slice(0, 8)
    Logger.debug("[Fork choice] Adding attestation #{id} to the store")

    state =
      case Handlers.on_attestation(state, attestation, false) do
        {:ok, new_state} -> new_state
        _ -> state
      end

    persist_fork_choice_store(state)
  end

  @spec notify_attester_slashing(Types.AttesterSlashing.t()) :: :ok
  def notify_attester_slashing(attester_slashing) do
    Logger.info("[Fork choice] Adding attester slashing to the store")
    state = fetch_fork_choice_store!()

    state =
      case Handlers.on_attester_slashing(state, attester_slashing) do
        {:ok, new_state} ->
          new_state

        _ ->
          Logger.error("[Fork choice] Failed to add attester slashing to the store")
          state
      end

    persist_fork_choice_store(state)
  end

  @spec on_tick(Types.uint64()) :: :ok
  def on_tick(time) do
    Logger.info("[ForkChoice] On tick!")
    store = fetch_fork_choice_store!()
    %Store{finalized_checkpoint: last_finalized_checkpoint} = store

    new_store = Handlers.on_tick(store, time)
    %Store{finalized_checkpoint: new_finalized_checkpoint} = new_store
    prune_old_states(last_finalized_checkpoint.epoch, new_finalized_checkpoint.epoch)
    persist_fork_choice_store(new_store)
  end

  ##########################
  ### Private Functions
  ##########################

  defp prune_old_states(last_finalized_epoch, new_finalized_epoch) do
    if last_finalized_epoch < new_finalized_epoch do
      new_finalized_slot =
        new_finalized_epoch * ChainSpec.get("SLOTS_PER_EPOCH")

      Task.start_link(StateDb, :prune_states_older_than, [new_finalized_slot])
      Task.start_link(BlockDb, :prune_blocks_older_than, [new_finalized_slot])
    end
  end

  @spec apply_handler(any(), any(), any()) :: any()
  defp apply_handler(iter, state, handler) do
    iter
    |> Enum.reduce_while({:ok, state}, fn
      x, {:ok, st} -> {:cont, handler.(st, x)}
      _, {:error, _} = err -> {:halt, err}
    end)
  end

  defp process_block(_block_root, %SignedBeaconBlock{} = signed_block, store) do
    with {:ok, new_store} <- Handlers.on_block(store, signed_block),
         # process block attestations
         {:ok, new_store} <-
           signed_block.message.body.attestations
           |> apply_handler(new_store, &Handlers.on_attestation(&1, &2, true)),
         # process block attester slashings
         {:ok, new_store} <-
           signed_block.message.body.attester_slashings
           |> apply_handler(new_store, &Handlers.on_attester_slashing/2) do
      {:ok, Handlers.prune_checkpoint_states(new_store)}
    end
  end

  @spec recompute_head(Store.t()) :: :ok
  def recompute_head(store) do
    persist_store(store)
    {:ok, head_root} = Head.get_head(store)
    head_block = Blocks.get_block!(head_root)

    Handlers.notify_forkchoice_update(store, head_block)

    %{slot: slot, body: body} = head_block

    OperationsCollector.notify_new_block(head_block)
    ValidatorManager.notify_new_block(slot, head_root)
    ExecutionChain.notify_new_block(slot, body.eth1_data, body.execution_payload)

    BeaconChain.update_fork_choice_cache(
      head_root,
      slot,
      store.justified_checkpoint,
      store.finalized_checkpoint
    )

    Logger.debug("[Fork choice] Updated fork choice cache", slot: slot)

    :ok
  end

  defp persist_store(store) do
    pruned_store = Map.put(store, :checkpoint_states, %{})

    Task.start_link(fn ->
      StoreDb.persist_store(pruned_store)
      Logger.debug("[Fork choice] Store persisted")
    end)
  end

  defp persist_fork_choice_store(store) do
    :telemetry.span([:fork_choice, :persist], %{}, fn ->
      {StoreDb.persist_fork_choice_store(store), %{}}
    end)
  end

  defp fetch_fork_choice_store!() do
    {:ok, store} =
      :telemetry.span([:fork_choice, :fetch], %{}, fn ->
        {StoreDb.fetch_fork_choice_store(), %{}}
      end)

    store
  end
end
