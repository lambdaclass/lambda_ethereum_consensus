defmodule LambdaEthereumConsensus.Store.BlockDb do
  @moduledoc """
  Storage and retrieval of blocks.
  """
  require Logger
  alias LambdaEthereumConsensus.Store.BlockBySlot
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.BlockInfo

  @block_prefix "blockHash"
  @block_status_prefix "blockStatus"

  @spec store_block_info(BlockInfo.t()) :: :ok
  def store_block_info(%BlockInfo{} = block_info) do
    # TODO handle encoding errors properly.
    {:ok, encoded} = BlockInfo.encode(block_info)
    key = block_key(block_info.root)
    Db.put(key, encoded)

    # WARN: this overrides any previous mapping for the same slot
    # TODO: this should apply fork-choice if not applied elsewhere
    # TODO: handle cases where slot is empty
    if not is_nil(block_info.signed_block) do
      BlockBySlot.put(block_info.signed_block.message.slot, block_info.root)
    end
  end

  @spec get_block_info(Types.root()) ::
          {:ok, BlockInfo.t()} | {:error, String.t()} | :not_found
  def get_block_info(block_root) do
    with {:ok, data} <- Db.get(block_key(block_root)) do
      BlockInfo.decode(block_root, data)
    end
  end

  @spec get_block_info_by_slot(Types.slot()) ::
          {:ok, BlockInfo.t()} | {:error, String.t()} | :not_found | :empty_slot
  def get_block_info_by_slot(slot) do
    # WARN: this will return the latest block received for the given slot
    # TODO: Are we actually saving empty slots in this index?
    case BlockBySlot.get(slot) do
      {:ok, :empty_slot} -> :empty_slot
      {:ok, root} -> get_block_info(root)
      other -> other
    end
  end

  @spec remove_root_from_status(Types.root(), BlockInfo.block_status()) :: :ok
  def remove_root_from_status(root, status) do
    get_roots_with_status(status)
    |> MapSet.delete(root)
    |> store_roots_with_status(status)
  end

  @spec add_root_to_status(Types.root(), BlockInfo.block_status()) :: :ok
  def add_root_to_status(root, status) do
    get_roots_with_status(status)
    |> MapSet.put(root)
    |> store_roots_with_status(status)
  end

  def change_root_status(root, from_status, to_status) do
    remove_root_from_status(root, from_status)
    add_root_to_status(root, to_status)

    # TODO: if we need to perform some level of db recovery, we probably should consider the
    # blocks db as the source of truth and reconstruct the status ones. Either that or
    # perform an ACID-like transaction.
  end

  @spec store_roots_with_status(MapSet.t(Types.root()), BlockInfo.block_status()) :: :ok
  defp store_roots_with_status(block_roots, status) do
    Db.put(block_status_key(status), :erlang.term_to_binary(block_roots))
  end

  @spec get_roots_with_status(BlockInfo.block_status()) :: MapSet.t(Types.root())
  def get_roots_with_status(status) do
    case Db.get(block_status_key(status)) do
      {:ok, binary} -> :erlang.binary_to_term(binary)
      :not_found -> MapSet.new([])
    end
  end

  @spec prune_blocks_older_than(non_neg_integer()) :: :ok | {:error, String.t()} | :not_found
  def prune_blocks_older_than(slot) do
    Logger.info("[BlockDb] Pruning started.", slot: slot)

    # TODO: the separate get operation is avoided if we implement folding with values in KvSchema.
    n_removed =
      BlockBySlot.fold_keys(slot, 0, fn slot, acc ->
        case BlockBySlot.get(slot) do
          {:ok, :empty_slot} ->
            BlockBySlot.delete(slot)
            acc + 1

          {:ok, block_root} ->
            BlockBySlot.delete(slot)
            Db.delete(block_key(block_root))
            acc + 1

          other ->
            Logger.error(
              "[Block pruning] Failed to remove block from slot #{inspect(slot)}. Reason: #{inspect(other)}"
            )
        end
      end)

    Logger.info("[BlockDb] Pruning finished. #{n_removed} blocks removed.")
  end

  defp block_key(root), do: Utils.get_key(@block_prefix, root)
  defp block_status_key(status), do: Utils.get_key(@block_status_prefix, Atom.to_string(status))
end
