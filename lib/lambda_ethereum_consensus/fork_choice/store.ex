defmodule LambdaEthereumConsensus.ForkChoice.Store do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  use GenServer
  require Logger

  alias LambdaEthereumConsensus.ForkChoice.{Handlers, Helpers}
  alias LambdaEthereumConsensus.Store.{BlockStore, StateStore}
  alias SszTypes.BeaconState
  alias SszTypes.SignedBeaconBlock
  alias SszTypes.Store

  ##########################
  ### Public API
  ##########################

  @spec start_link([BeaconState.t()]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get_finalized_checkpoint() :: {:ok, SszTypes.Checkpoint.t()}
  def get_finalized_checkpoint do
    [finalized_checkpoint] = get_store_attrs([:finalized_checkpoint])
    {:ok, finalized_checkpoint}
  end

  @spec get_current_slot() :: integer()
  def get_current_slot do
    [time, genesis_time] = get_store_attrs([:time, :genesis_time])
    div(time - genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end

  @spec has_block?(SszTypes.root()) :: boolean()
  def has_block?(block_root) do
    [blocks] = get_store_attrs([:blocks])
    Map.has_key?(blocks, block_root)
  end

  @spec on_block(SszTypes.SignedBeaconBlock.t(), SszTypes.root()) :: :ok
  def on_block(signed_block, block_root) do
    :ok = BlockStore.store_block(signed_block)
    GenServer.cast(__MODULE__, {:on_block, block_root, signed_block})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init({BeaconState.t(), SignedBeaconBlock.t()}) :: {:ok, Store.t()} | {:stop, any}
  def init({anchor_state = %BeaconState{}, signed_anchor_block = %SignedBeaconBlock{}}) do
    result =
      case Helpers.get_forkchoice_store(anchor_state, signed_anchor_block.message) do
        {:ok, store = %Store{}} ->
          store = on_tick_now(store)
          Logger.info("[Fork choice] Initialized store.")
          {:ok, store}

        {:error, error} ->
          {:stop, error}
      end

    # TODO: this should be done after validation
    :ok = StateStore.store_state(anchor_state)
    :ok = BlockStore.store_block(signed_anchor_block)
    schedule_next_tick()
    result
  end

  @impl GenServer
  def handle_call({:get_store_attrs, attrs}, _from, state) do
    values = Enum.map(attrs, &Map.fetch!(state, &1))
    {:reply, values, state}
  end

  @impl GenServer
  def handle_cast({:on_block, block_root, signed_block}, state) do
    Logger.info("[Fork choice] Adding block #{block_root} to the store.")

    state =
      case Handlers.on_block(state, signed_block) do
        {:ok, state} ->
          Map.put(state, :blocks, Map.put(state.blocks, block_root, signed_block.message))

        _ ->
          state
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:on_tick, store) do
    new_store = on_tick_now(store)

    schedule_next_tick()
    {:noreply, new_store}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec get_store_attrs([atom()]) :: [any()]
  defp get_store_attrs(attrs) do
    GenServer.call(__MODULE__, {:get_store_attrs, attrs})
  end

  defp on_tick_now(store), do: Handlers.on_tick(store, :os.system_time(:second))

  defp schedule_next_tick do
    # For millisecond precision
    time_to_next_tick = 1000 - rem(:os.system_time(:millisecond), 1000)
    Process.send_after(self(), :on_tick, time_to_next_tick)
  end
end
