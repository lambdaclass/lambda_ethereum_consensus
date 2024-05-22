defmodule LambdaEthereumConsensus.Store.BlockDb do
  @moduledoc """
  Storage and retrieval of blocks.
  """
  require Logger
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.SignedBeaconBlock

  @block_prefix "blockHash"
  @blockslot_prefix "blockSlot"

  @spec store_block(SignedBeaconBlock.t(), Types.root()) :: :ok
  def store_block(%SignedBeaconBlock{} = signed_block) do
    store_block(signed_block, Ssz.hash_tree_root!(signed_block.message))
  end

  def store_block(%SignedBeaconBlock{} = signed_block, block_root) do
    {:ok, encoded_signed_block} = Ssz.to_ssz(signed_block)

    key = block_key(block_root)
    Db.put(key, encoded_signed_block)

    # WARN: this overrides any previous mapping for the same slot
    # TODO: this should apply fork-choice if not applied elsewhere
    # TODO: handle cases where slot is empty
    slothash_key = block_root_by_slot_key(signed_block.message.slot)
    Db.put(slothash_key, block_root)
  end

  @spec get_block(Types.root()) ::
          {:ok, SignedBeaconBlock.t()} | {:error, String.t()} | :not_found
  def get_block(block_root) do
    key = block_key(block_root)

    with {:ok, signed_block} <- Db.get(key) do
      Ssz.from_ssz(signed_block, SignedBeaconBlock)
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

  @spec get_block_by_slot(Types.slot()) ::
          {:ok, SignedBeaconBlock.t()} | {:error, String.t()} | :not_found | :empty_slot
  def get_block_by_slot(slot) do
    # WARN: this will return the latest block received for the given slot
    with {:ok, root} <- get_block_root_by_slot(slot) do
      get_block(root)
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

  def stream_blocks() do
    Stream.resource(
      fn -> <<0::256>> |> block_key() |> init_cursor() end,
      &next_block/1,
      &close_cursor/1
    )
  end

  defp init_cursor(initial_key) do
    with {:ok, it} <- Db.iterate(),
         {:ok, _, _} <- Exleveldb.iterator_move(it, initial_key),
         {:ok, _, _} <- Exleveldb.iterator_move(it, :prev) do
      it
    else
      # DB is empty
      {:error, :invalid_iterator} -> nil
    end
  end

  defp next_block(nil), do: {:halt, nil}

  defp next_block(it) do
    case Exleveldb.iterator_move(it, :prefetch) do
      {:ok, @block_prefix <> <<hash::binary-size(32)>>, value} ->
        {:ok, block} = Ssz.from_ssz(value, SignedBeaconBlock)
        {[{hash, block.message}], it}

      _ ->
        {:halt, it}
    end
  end
end
