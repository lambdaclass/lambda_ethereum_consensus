defmodule LambdaEthereumConsensus.Store.BlockStates do
  @moduledoc false
  alias LambdaEthereumConsensus.Store.StateStore

  use GenServer

  @ets_state_by_block __MODULE__

  ##########################
  ### Public API
  ##########################

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def store_state(block_root, beacon_state) do
    cache_state(block_root, beacon_state)
    GenServer.cast(__MODULE__, {:store_state, block_root, beacon_state})
  end

  def get_state(block_root), do: lookup(block_root)

  @spec clear() :: any()
  def clear, do: :ets.delete_all_objects(@ets_state_by_block)

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  def init(_) do
    :ets.new(@ets_state_by_block, [:set, :public, :named_table])
    {:ok, nil}
  end

  @impl GenServer
  def handle_cast({:store_state, block_root, beacon_state}, state) do
    StateStore.store_state(beacon_state, block_root)
    # TODO: remove old states from cache
    {:noreply, state}
  end

  ##########################
  ### Private Functions
  ##########################

  defp lookup(block_root) do
    case :ets.lookup_element(@ets_state_by_block, block_root, 2, nil) do
      nil -> cache_miss(block_root)
      state -> state
    end
  end

  defp cache_miss(block_root) do
    case fetch_state(block_root) do
      nil -> nil
      state -> cache_state(block_root, state)
    end
  end

  defp fetch_state(block_root) do
    case StateStore.get_state(block_root) do
      {:ok, beacon_state} -> beacon_state
      :not_found -> nil
      # TODO: handle this somehow?
      {:error, error} -> raise "database error #{inspect(error)}"
    end
  end

  defp cache_state(block_root, beacon_state) do
    :ets.insert_new(@ets_state_by_block, {block_root, beacon_state})
  end
end
