defmodule LambdaEthereumConsensus.Store.Blocks do
  @moduledoc """
  Interface to `Store.blocks`.
  """
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.LRUCache
  alias Types.BeaconBlock
  alias Types.BlockInfo

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

  @spec add_block_to_download(Types.root()) :: :ok
  def add_block_to_download(root) do
    %BlockInfo{root: root, status: :download, signed_block: nil}
    # |> Metrics.block_status(:download)
    |> new_block_info()
  end

  # TODO: make private.
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

  @spec new_block_info(BlockInfo.t()) :: :ok
  def new_block_info(block_info) do
    store_block_info(block_info)

    # We add the root to the status list, but we also make sure we remove it from the downloads
    # list. If it's not in the list, the operation is equivalent to only adding it in the correct
    # one.
    BlockDb.change_root_status(block_info.root, :download, block_info.status)

    # Metrics.block_status(block_info, :download)
  end

  @doc """
  Changes the status of a block in the db. Returns the block with the modified status.
  """
  @spec change_status(BlockInfo.t(), BlockInfo.block_status()) :: BlockInfo.t()
  def change_status(block_info, status) do
    new_block_info = BlockInfo.change_status(block_info, status)
    store_block_info(new_block_info)

    old_status = block_info.status
    BlockDb.change_root_status(block_info.root, old_status, status)
    # Metrics.block_status(new_block_info, old_status)
    new_block_info
  end

  @spec get_blocks_with_status(BlockInfo.block_status()) ::
          {:ok, [BlockInfo.t()]} | {:error, binary()}
  def get_blocks_with_status(status) do
    BlockDb.get_roots_with_status(status)
    |> Enum.reduce_while([], fn root, acc ->
      case get_block_info(root) do
        nil -> {:halt, root}
        block_info -> {:cont, [block_info | acc]}
      end
    end)
    |> case do
      block_info when is_list(block_info) ->
        {:ok, Enum.reverse(block_info)}

      root ->
        {:error, "Error getting blocks with status #{status}. Block with root #{root} not found."}
    end
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
