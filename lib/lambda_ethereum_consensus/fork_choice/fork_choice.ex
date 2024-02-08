defmodule LambdaEthereumConsensus.ForkChoice do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  use GenServer
  require Logger

  alias LambdaEthereumConsensus.Store.StoreStorage
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.ForkChoice.{Handlers, Helpers}
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.Attestation
  alias Types.BeaconState
  alias Types.SignedBeaconBlock
  alias Types.Store

  ##########################
  ### Public API
  ##########################

  @spec start_link({BeaconState.t(), SignedBeaconBlock.t(), Types.uint64()}) ::
          :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec on_tick(Types.uint64()) :: :ok
  def on_tick(time) do
    GenServer.cast(__MODULE__, {:on_tick, time})
  end

  @spec on_block(Types.SignedBeaconBlock.t(), Types.root()) :: :ok | :error
  def on_block(signed_block, block_root) do
    GenServer.cast(__MODULE__, {:on_block, block_root, signed_block, self()})
  end

  @spec on_attestation(Types.Attestation.t()) :: :ok
  def on_attestation(%Attestation{} = attestation) do
    GenServer.cast(__MODULE__, {:on_attestation, attestation})
  end

  @spec notify_attester_slashing(Types.AttesterSlashing.t()) :: :ok
  def notify_attester_slashing(attester_slashing) do
    GenServer.cast(__MODULE__, {:attester_slashing, attester_slashing})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init({Store.t(), Types.slot(), Types.uint64()}) :: {:ok, Store.t()} | {:stop, any}
  def init({%Store{} = store, head_slot, time}) do
    Logger.info("[Fork choice] Initialized store.", slot: head_slot)

    store = Handlers.on_tick(store, time)

    :telemetry.execute([:sync, :store], %{slot: Store.get_current_slot(store)})
    :telemetry.execute([:sync, :on_block], %{slot: head_slot})

    {:ok, store}
  end

  @impl GenServer
  def handle_cast({:on_block, block_root, %SignedBeaconBlock{} = signed_block, from}, store) do
    slot = signed_block.message.slot

    result =
      :telemetry.span([:sync, :on_block], %{}, fn ->
        {process_block(block_root, signed_block, store), %{}}
      end)

    case result do
      {:ok, new_store} ->
        :telemetry.execute([:sync, :on_block], %{slot: slot})
        Logger.info("[Fork choice] New block added", slot: slot, root: block_root)

        Task.async(__MODULE__, :recompute_head, [new_store])

        GenServer.cast(from, {:block_processed, block_root, true})
        {:noreply, new_store}

      {:error, reason} ->
        Logger.error("[Fork choice] Failed to add block: #{reason}", slot: slot)
        GenServer.cast(from, {:block_processed, block_root, false})
        {:noreply, store}
    end
  end

  @impl GenServer
  def handle_cast({:on_attestation, %Attestation{} = attestation}, %Store{} = state) do
    id = attestation.signature |> Base.encode16() |> String.slice(0, 8)
    Logger.debug("[Fork choice] Adding attestation #{id} to the store")

    state =
      case Handlers.on_attestation(state, attestation, false) do
        {:ok, new_state} -> new_state
        _ -> state
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:attester_slashing, attester_slashing}, state) do
    Logger.info("[Fork choice] Adding attester slashing to the store")

    state =
      case Handlers.on_attester_slashing(state, attester_slashing) do
        {:ok, new_state} ->
          new_state

        _ ->
          Logger.error("[Fork choice] Failed to add attester slashing to the store")
          state
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:on_tick, time}, store) do
    new_store = Handlers.on_tick(store, time)
    {:noreply, new_store}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec apply_handler(any(), any(), any()) :: any()
  def apply_handler(iter, state, handler) do
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
    {:ok, head_root} = Helpers.get_head(store)
    head_block = Blocks.get_block!(head_root)

    Handlers.notify_forkchoice_update(store, head_block)

    finalized_checkpoint = store.finalized_checkpoint

    BeaconChain.update_fork_choice_cache(
      head_root,
      head_block.slot,
      store.justified_checkpoint,
      finalized_checkpoint
    )

    Logger.debug("[Fork choice] Updated fork choice cache", slot: head_block.slot)

    :ok
  end

  def persist_store(store) do
    pruned_store = Map.put(store, :checkpoint_states, %{})

    Task.async(fn ->
      StoreStorage.persist_store(pruned_store)
      Logger.debug("[Fork choice] Store persisted")
    end)
  end
end
