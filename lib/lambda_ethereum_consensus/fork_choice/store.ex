defmodule LambdaEthereumConsensus.ForkChoice.Store do
  @moduledoc """
    The Store is responsible for tracking information required for the fork choice algorithm.
  """

  use GenServer
  require Logger

  alias LambdaEthereumConsensus.ForkChoice.Utils
  alias LambdaEthereumConsensus.Store.{BlockStore, StateStore}
  alias SszTypes.BeaconBlock
  alias SszTypes.BeaconState
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
    store = get_state()
    {:ok, store.finalized_checkpoint}
  end

  @spec get_current_slot() :: integer()
  def get_current_slot do
    store = get_state()
    div(store.time - store.genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end

  @spec has_block?(SszTypes.root()) :: boolean()
  def has_block?(block_root) do
    state = get_state()
    Map.has_key?(state.blocks, block_root)
  end

  @spec on_block(SszTypes.BeaconBlock.t()) :: :ok
  def on_block(block) do
    {:ok, block_root} = Ssz.hash_tree_root(block)
    GenServer.cast(__MODULE__, {:on_block, block_root, block})
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init({BeaconState.t(), BeaconBlock.t()}) :: {:ok, Store.t()} | {:stop, any}
  def init({anchor_state = %BeaconState{}, anchor_block = %BeaconBlock{}}) do
    result =
      case Utils.get_forkchoice_store(anchor_state, anchor_block) do
        {:ok, store = %Store{}} ->
          Logger.info("[Fork choice] Initialized store.")
          {:ok, store}

        {:error, error} ->
          {:stop, error}
      end

    # TODO: this should be done after validation
    :ok = StateStore.store_state(anchor_state)
    :ok = BlockStore.store_block(anchor_block)
    result
  end

  @impl GenServer
  def handle_call({:get_state}, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast({:on_block, block_root, block}, state) do
    Logger.info("[Fork choice] Adding block #{block_root} to the store.")
    :ok = BlockStore.store_block(block)
    {:noreply, Map.put(state, :blocks, Map.put(state.blocks, block_root, block))}
  end

  ##########################
  ### Private Functions
  ##########################

  @spec get_state() :: Store.t()
  defp get_state do
    GenServer.call(__MODULE__, {:get_state})
  end
end
