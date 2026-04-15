defmodule LambdaEthereumConsensus.Store.BlockStates do
  @moduledoc """
  Interface to `Store.block_states`.
  """
  alias LambdaEthereumConsensus.Store.LRUCache
  alias LambdaEthereumConsensus.Store.StateDb
  alias Types.StateInfo

  @table :states_by_block_hash
  # Each BeaconState is ~460MB on Hoodi (~200K validators) and ~775MB on mainnet
  # (~1.2M validators). With 10 entries on mainnet, the cache uses ~7.7GB.
  # 6 entries caused frequent cache misses triggering 30s+ LevelDB reads that
  # blocked the Libp2pPort GenServer. 10 entries balances memory (7.7 GB) with
  # cache hit rate. Previously 16 (12.4 GB, OOM during epoch processing) and
  # before that 128 (55+ GB, swap thrashing).
  @max_entries 10
  @batch_prune_size 2

  ##########################
  ### Public API
  ##########################

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    LRUCache.start_link(
      table: @table,
      max_entries: @max_entries,
      batch_prune_size: @batch_prune_size,
      # NOTE: LevelDB persistence is handled by the caller (handlers.ex uses
      # Task.Supervisor for async writes). The LRU cache only manages ETS caching.
      # Previously this was synchronous and blocked the Libp2pPort GenServer for
      # 30-60s during state serialization+write.
      store_func: fn _k, _v -> :ok end
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec store_state_info(StateInfo.t()) :: :ok
  def store_state_info(state_info), do: LRUCache.put_cache(@table, state_info.root, state_info)

  @spec get_state_info(Types.root()) :: StateInfo.t() | nil
  def get_state_info(block_root), do: LRUCache.get(@table, block_root, &fetch_state/1)

  @spec get_state_info!(Types.root()) :: StateInfo.t()
  def get_state_info!(block_root) do
    case get_state_info(block_root) do
      nil -> raise "State not found: 0x#{Base.encode16(block_root, case: :lower)}"
      v -> v
    end
  end

  @doc """
  Touch a cache entry to refresh its TTL without fetching or inserting.
  Used to prevent parent state eviction during long prefetch operations.
  """
  @spec touch(Types.root()) :: :ok
  def touch(block_root), do: LRUCache.touch(@table, block_root)

  ##########################
  ### Private Functions
  ##########################

  defp fetch_state(key) do
    case StateDb.get_state_by_block_root(key) do
      {:ok, value} -> value
      :not_found -> nil
      # TODO: handle this somehow?
      {:error, error} -> raise "database error #{inspect(error)}"
    end
  end
end
