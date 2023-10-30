defmodule LambdaEthereumConsensus.Store.BlockStore do
  @moduledoc """
  Storage and retrieval of blocks.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils

  @block_prefix "block"
  @blockslot_prefix @block_prefix <> "slot"

  @spec store_block(SszTypes.SignedBeaconBlock.t()) :: :ok
  def store_block(%SszTypes.SignedBeaconBlock{} = block) do
    {:ok, block_root} = Ssz.hash_tree_root(block)
    {:ok, encoded_block} = Ssz.to_ssz(block)

    key = block_key(block_root)
    Db.put(key, encoded_block)

    # WARN: this overrides any previous mapping for the same slot
    # TODO: this should apply fork-choice if not applied elsewhere
    slothash_key = block_root_by_slot_key(block.slot)
    Db.put(slothash_key, block_root)
  end

  @spec get_block(SszTypes.root()) ::
          {:ok, SszTypes.SignedBeaconBlock.t()} | {:error, String.t()} | :not_found
  def get_block(block_root) do
    key = block_key(block_root)

    with {:ok, block} <- Db.get(key) do
      Ssz.from_ssz(block, SszTypes.SignedBeaconBlock)
    end
  end

  @spec get_block_root_by_slot(SszTypes.slot()) ::
          {:ok, SszTypes.root()} | {:error, String.t()} | :not_found
  def get_block_root_by_slot(slot) do
    key = block_root_by_slot_key(slot)
    Db.get(key)
  end

  @spec get_block_by_slot(SszTypes.slot()) ::
          {:ok, SszTypes.SignedBeaconBlock.t()} | {:error, String.t()} | :not_found
  def get_block_by_slot(slot) do
    # WARN: this will return the latest block received for the given slot
    with {:ok, root} <- get_block_root_by_slot(slot) do
      get_block(root)
    end
  end

  def stream_missing_blocks_desc do
    Stream.resource(
      fn -> init_cursor(0xFFFFFFFFFFFFFFFF) end,
      &next_slot(&1, :prev),
      &close_cursor/1
    )
    # TODO: we should remove this when we have a genesis block
    |> Stream.concat([-1])
    |> Stream.transform(nil, &get_missing_desc/2)
  end

  def stream_missing_blocks_asc(starting_slot) do
    [starting_slot - 1]
    |> Stream.concat(
      Stream.resource(
        fn -> init_cursor(starting_slot) end,
        &next_slot(&1, :next),
        &close_cursor/1
      )
    )
    |> Stream.transform(nil, &get_missing_asc/2)
  end

  defp init_cursor(starting_slot) do
    initial_key = block_root_by_slot_key(starting_slot)

    with {:ok, it} <- Db.iterate_keys(),
         {:ok, key} <- Exleveldb.iterator_move(it, initial_key),
         {:ok, _} <-
           if(key == initial_key, do: Exleveldb.iterator_move(it, :prev), else: {:ok, nil}) do
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

  def get_missing_desc(slot, nil), do: {[], slot}
  def get_missing_desc(slot, prev), do: {(prev - 1)..(slot + 1)//-1, slot}

  def get_missing_asc(slot, nil), do: {[], slot}
  def get_missing_asc(slot, prev), do: {(prev + 1)..(slot - 1)//1, slot}

  defp block_key(root), do: Utils.get_key(@block_prefix, root)
  defp block_root_by_slot_key(slot), do: Utils.get_key(@blockslot_prefix, slot)
end
