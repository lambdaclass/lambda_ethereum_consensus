defmodule LambdaEthereumConsensus.Store.BlockDb do
  @moduledoc """
  Storage and retrieval of blocks.
  """
  require Logger
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.BlockInfo

  @block_prefix "blockHash"
  @blockslot_prefix "blockSlot"
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
      slothash_key = block_root_by_slot_key(block_info.signed_block.message.slot)
      Db.put(slothash_key, block_info.root)
    end
  end

  @spec get_block_info(Types.root()) ::
          {:ok, BlockInfo.t()} | {:error, String.t()} | :not_found
  def get_block_info(block_root) do
    with {:ok, data} <- Db.get(block_key(block_root)) do
      BlockInfo.decode(block_root, data)
    end
  end

  @spec get_block_root_by_slot(Types.slot()) ::
          {:ok, Types.root()} | {:error, String.t()} | :not_found | :empty_slot
  def get_block_root_by_slot(slot) do
    key = block_root_by_slot_key(slot)
    block = Db.get(key)

    case block do
      {:ok, <<>>} -> :empty_slot
      _ -> block
    end
  end

  @spec get_block_info_by_slot(Types.slot()) ::
          {:ok, BlockInfo.t()} | {:error, String.t()} | :not_found | :empty_slot
  def get_block_info_by_slot(slot) do
    # WARN: this will return the latest block received for the given slot
    with {:ok, root} <- get_block_root_by_slot(slot) do
      get_block_info(root)
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
    initial_key = slot |> block_root_by_slot_key()

    slots_to_remove =
      Stream.resource(
        fn -> init_keycursor(initial_key) end,
        &next_slot(&1, :prev),
        &close_cursor/1
      )
      |> Enum.to_list()

    slots_to_remove |> Enum.each(&remove_block_by_slot/1)
    Logger.info("[BlockDb] Pruning finished. #{Enum.count(slots_to_remove)} blocks removed.")
  end

  @spec remove_block_by_slot(non_neg_integer()) :: :ok | :not_found
  defp remove_block_by_slot(slot) do
    slothash_key = block_root_by_slot_key(slot)

    with {:ok, block_root} <- Db.get(slothash_key) do
      key_block = block_key(block_root)
      Db.delete(slothash_key)
      Db.delete(key_block)
    end
  end

  defp init_keycursor(initial_key) do
    with {:ok, it} <- Db.iterate_keys(),
         {:ok, _key} <- Exleveldb.iterator_move(it, initial_key) do
      it
    else
      # DB is empty
      {:error, :invalid_iterator} -> nil
    end
  end

  defp next_slot(nil, _movement), do: {:halt, nil}

  defp next_slot(it, movement) do
    case Exleveldb.iterator_move(it, movement) do
      {:ok, @blockslot_prefix <> <<key::64>>} ->
        {[key], it}

      _ ->
        {:halt, it}
    end
  end

  defp close_cursor(nil), do: :ok
  defp close_cursor(it), do: :ok = Exleveldb.iterator_close(it)

  defp block_key(root), do: Utils.get_key(@block_prefix, root)
  defp block_root_by_slot_key(slot), do: Utils.get_key(@blockslot_prefix, slot)

  defp block_status_key(status), do: Utils.get_key(@block_status_prefix, Atom.to_string(status))
end
