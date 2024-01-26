defmodule LambdaEthereumConsensus.Store.BlockStates do
  @moduledoc """
  Interface to `Store.block_states`.
  """
  alias LambdaEthereumConsensus.Store.LRUCache
  alias LambdaEthereumConsensus.Store.StateStore
  alias Types.BeaconState

  @table :states_by_block_hash
  @max_entries 128
  @batch_prune_size 16

  ##########################
  ### Public API
  ##########################

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    LRUCache.start_link(
      table: @table,
      max_entries: @max_entries,
      batch_prune_size: @batch_prune_size,
      store_func: &StateStore.store_state(&2, &1)
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec store_state(Types.root(), BeaconState.t()) :: :ok
  def store_state(block_root, state), do: LRUCache.put(@table, block_root, state)

  @spec get_state(Types.root()) :: BeaconState.t() | nil
  def get_state(block_root), do: LRUCache.get(@table, block_root, &fetch_state/1)

  @spec get_state!(Types.root()) :: BeaconState.t()
  def get_state!(block_root) do
    case get_state(block_root) do
      nil -> raise "State not found: 0x#{Base.encode16(block_root, case: :lower)}"
      v -> v
    end
  end

  ##########################
  ### Private Functions
  ##########################

  defp fetch_state(key) do
    case StateStore.get_state_by_block_root(key) do
      {:ok, value} -> value
      :not_found -> nil
      # TODO: handle this somehow?
      {:error, error} -> raise "database error #{inspect(error)}"
    end
  end
end
