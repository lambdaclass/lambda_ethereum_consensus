defmodule LambdaEthereumConsensus.Store.Blocks do
  @moduledoc """
  Interface to `Store.blocks`.
  """
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.LRUCache
  alias Types.BeaconBlock
  alias Types.SignedBeaconBlock

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
      store_func: &BlockDb.store_block(&2, &1)
    )
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @spec store_block(Types.root(), SignedBeaconBlock.t()) :: :ok
  def store_block(block_root, signed_block), do: LRUCache.put(@table, block_root, signed_block)

  @spec get_signed_block(Types.root()) :: SignedBeaconBlock.t() | nil
  def get_signed_block(block_root), do: LRUCache.get(@table, block_root, &fetch_block/1)

  @spec get_signed_block!(Types.root()) :: SignedBeaconBlock.t()
  def get_signed_block!(block_root) do
    case LRUCache.get(@table, block_root, &fetch_block/1) do
      nil -> raise "Block not found: 0x#{Base.encode16(block_root, case: :lower)}"
    end
  end

  @spec get_block(Types.root()) :: BeaconBlock.t() | nil
  def get_block(block_root) do
    case get_signed_block(block_root) do
      nil -> nil
      %{message: block} -> block
    end
  end

  @spec has_block?(Types.root()) :: boolean()
  def has_block?(block_root), do: not (get_signed_block(block_root) |> is_nil())

  @spec get_block!(Types.root()) :: BeaconBlock.t()
  def get_block!(block_root) do
    case get_block(block_root) do
      nil -> raise "Block not found: 0x#{Base.encode16(block_root, case: :lower)}"
      v -> v
    end
  end

  ##########################
  ### Private Functions
  ##########################

  defp fetch_block(key) do
    case BlockDb.get_block(key) do
      {:ok, value} -> value
      :not_found -> nil
      # TODO: handle this somehow?
      {:error, error} -> raise "database error #{inspect(error)}"
    end
  end
end
