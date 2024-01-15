defmodule LambdaEthereumConsensus.ForkChoice do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  use GenServer
  require Logger

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Execution.ExecutionClient
  alias LambdaEthereumConsensus.ForkChoice.{Handlers, Helpers}
  alias LambdaEthereumConsensus.Store.{BlockStore, StateStore}
  alias Types.Attestation
  alias Types.BeaconState
  alias Types.SignedBeaconBlock
  alias Types.Store

  @default_timeout 100_000

  ##########################
  ### Public API
  ##########################

  @spec start_link({BeaconState.t(), SignedBeaconBlock.t(), Types.uint64()}) ::
          :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_finalized_checkpoint() :: {:ok, Types.Checkpoint.t()}
  def get_finalized_checkpoint do
    [finalized_checkpoint] = get_store_attrs([:finalized_checkpoint])
    {:ok, finalized_checkpoint}
  end

  @spec get_justified_checkpoint() :: {:ok, Types.Checkpoint.t()}
  def get_justified_checkpoint do
    [justified_checkpoint] = get_store_attrs([:justified_checkpoint])
    {:ok, justified_checkpoint}
  end

  @spec has_block?(Types.root()) :: boolean()
  def has_block?(block_root) do
    block = get_block(block_root)
    block != nil
  end

  @spec on_tick(Types.uint64()) :: :ok
  def on_tick(time) do
    GenServer.cast(__MODULE__, {:on_tick, time})
  end

  @spec on_block(Types.SignedBeaconBlock.t(), Types.root()) :: :ok | :error
  def on_block(signed_block, block_root) do
    :ok = BlockStore.store_block(signed_block)
    GenServer.call(__MODULE__, {:on_block, block_root, signed_block}, @default_timeout)
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
  @spec init({BeaconState.t(), SignedBeaconBlock.t(), Types.uint64()}) ::
          {:ok, Store.t()} | {:stop, any}
  def init({anchor_state = %BeaconState{}, signed_anchor_block = %SignedBeaconBlock{}, time}) do
    result =
      case Helpers.get_forkchoice_store(anchor_state, signed_anchor_block.message) do
        {:ok, store = %Store{}} ->
          store = Handlers.on_tick(store, time)
          Logger.info("[Fork choice] Initialized store.")
          {:ok, store}

        {:error, error} ->
          {:stop, error}
      end

    # TODO: this should be done after validation
    :ok = StateStore.store_state(anchor_state)
    :ok = BlockStore.store_block(signed_anchor_block)

    slot = signed_anchor_block.message.slot
    :telemetry.execute([:sync, :store], %{slot: slot})
    :telemetry.execute([:sync, :on_block], %{slot: slot})

    result
  end

  @impl GenServer
  def handle_call({:get_store_attrs, attrs}, _from, state) do
    values = Enum.map(attrs, &Map.fetch!(state, &1))
    {:reply, values, state}
  end

  @impl GenServer
  def handle_call(:get_current_status_message, _from, state) do
    {:reply, Helpers.current_status_message(state), state}
  end

  def handle_call({:get_block, block_root}, _from, state) do
    {:reply, Map.get(state.blocks, block_root), state}
  end

  @impl GenServer
  def handle_call({:on_block, block_root, %SignedBeaconBlock{} = signed_block}, _from, store) do
    slot = signed_block.message.slot

    result =
      :telemetry.span([:sync, :on_block], %{slot: slot}, fn ->
        {process_block(block_root, signed_block, store), %{slot: slot}}
      end)

    case result do
      {:ok, new_store} ->
        Logger.info("[Fork choice] Block #{slot} added to the store.")

        Task.async(__MODULE__, :recompute_head, [new_store])
        {:reply, :ok, new_store}

      {:error, reason} ->
        Logger.error("[Fork choice] Failed to add block #{slot} to the store: #{reason}")
        {:reply, :error, store}
    end
  end

  @impl GenServer
  def handle_cast({:on_attestation, %Attestation{} = attestation}, %Types.Store{} = state) do
    id = attestation.signature |> Base.encode16() |> String.slice(0, 8)
    Logger.debug("[Fork choice] Adding attestation #{id} to the store.")

    state =
      case Handlers.on_attestation(state, attestation, false) do
        {:ok, new_state} -> new_state
        _ -> state
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:attester_slashing, attester_slashing}, state) do
    Logger.info("[Fork choice] Adding attester slashing to the store.")

    state =
      case Handlers.on_attester_slashing(state, attester_slashing) do
        {:ok, new_state} ->
          new_state

        _ ->
          Logger.error("[Fork choice] Failed to add attester slashing to the store.")
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

  @spec get_block(Types.root()) :: Types.SignedBeaconBlock.t() | nil
  def get_block(block_root) do
    GenServer.call(__MODULE__, {:get_block, block_root}, @default_timeout)
  end

  @spec get_store_attrs([atom()]) :: [any()]
  defp get_store_attrs(attrs) do
    GenServer.call(__MODULE__, {:get_store_attrs, attrs}, @default_timeout)
  end

  @spec apply_handler(any(), any(), any()) :: any()
  def apply_handler(iter, state, handler) do
    iter
    |> Enum.reduce_while({:ok, state}, fn
      x, {:ok, st} -> {:cont, handler.(st, x)}
      _, {:error, _} = err -> {:halt, err}
    end)
  end

  defp process_block(block_root, %SignedBeaconBlock{} = signed_block, store) do
    with {:ok, new_store} <- Handlers.on_block(store, signed_block),
         # process block attestations
         {:ok, new_store} <-
           signed_block.message.body.attestations
           |> apply_handler(new_store, &Handlers.on_attestation(&1, &2, true)),
         # process block attester slashings
         {:ok, new_store} <-
           signed_block.message.body.attester_slashings
           |> apply_handler(new_store, &Handlers.on_attester_slashing/2) do
      BlockStore.store_block(signed_block)
      Map.fetch!(new_store.block_states, block_root) |> StateStore.store_state()
      {:ok, new_store}
    end
  end

  @spec recompute_head(Types.Store.t()) :: :ok
  def recompute_head(store) do
    {:ok, head_root} = Helpers.get_head(store)

    head_block = Map.get(store.blocks, head_root)
    finalized_checkpoint = store.finalized_checkpoint

    # TODO: do someting with the result from the execution client
    # TODO: compute safe block hash
    ExecutionClient.notify_forkchoice_updated(
      head_root,
      finalized_checkpoint.root,
      finalized_checkpoint.root
    )

    BeaconChain.update_fork_choice_cache(
      head_root,
      head_block.slot,
      finalized_checkpoint.root,
      finalized_checkpoint.epoch
    )

    :ok
  end
end
