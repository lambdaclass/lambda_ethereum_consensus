defmodule LambdaEthereumConsensus.Store.Blocks do
  @moduledoc """
  Interface to `Store.blocks`.
  """
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.BlockDb.BlockInfo
  alias LambdaEthereumConsensus.Store.LRUCache
  alias Types.BeaconBlock

  @table :blocks_by_hash
  @max_entries 512
  @batch_prune_size 32

  ##########################
  ### Public API
  ##########################

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    LRUCache.start_link(
      table: @table,
      max_entries: @max_entries,
      batch_prune_size: @batch_prune_size,
      store_func: fn _k, v -> BlockDb.store_block_info(v) end
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec store_block_info(BlockInfo.t()) :: :ok
  def store_block_info(block_info) do
    LRUCache.put(@table, block_info.root, block_info)
  end

  @spec get_block_info(Types.root()) :: BlockInfo.t() | nil
  def get_block_info(block_root), do: LRUCache.get(@table, block_root, &fetch_block_info/1)

  @spec get_block_info!(Types.root()) :: BlockInfo.t()
  def get_block_info!(block_root) do
    case LRUCache.get(@table, block_root, &fetch_block_info/1) do
      nil -> raise "Block not found: 0x#{Base.encode16(block_root, case: :lower)}"
    end
  end

  @spec get_block(Types.root()) :: BeaconBlock.t() | nil
  def get_block(block_root) do
    case get_block_info(block_root) do
      nil -> nil
      %{signed_block: %{message: block}} -> block
    end
  end

  @spec has_block?(Types.root()) :: boolean()
  def has_block?(block_root), do: not (get_block_info(block_root) |> is_nil())

  @spec get_block!(Types.root()) :: BeaconBlock.t()
  def get_block!(block_root) do
    case get_block(block_root) do
      nil -> raise "Block not found: 0x#{Base.encode16(block_root, case: :lower)}"
      v -> v
    end
  end

  @spec change_status(BlockInfo.t(), BlockInfo.status()) :: :ok
  def change_status(block_info, status) do
    block_info
    |> BlockInfo.change_status(status)
    |> store_block_info()
  end

  def get_blocks_with_status(_status) do
    # TODO
    []
  end

  ##########################
  ### Private Functions
  ##########################

  defp fetch_block_info(key) do
    case BlockDb.get_block_info(key) do
      {:ok, value} -> value
      :not_found -> nil
      # TODO: handle this somehow?
      {:error, error} -> raise "database error #{inspect(error)}"
    end
  end
end
