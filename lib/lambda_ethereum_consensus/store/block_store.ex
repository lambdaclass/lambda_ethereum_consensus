defmodule LambdaEthereumConsensus.Store.BlockStore do
  @moduledoc """
  Storage and retrieval of blocks.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils

  @block_prefix "block"
  @blockslot_prefix @block_prefix <> "slot"

  @spec store_block(SszTypes.BeaconBlock.t()) :: :ok
  def store_block(%SszTypes.BeaconBlock{} = block) do
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
          {:ok, SszTypes.BeaconBlock.t()} | {:error, String.t()} | :not_found
  def get_block(block_root) do
    key = block_key(block_root)

    with {:ok, block} <- Db.get(key) do
      Ssz.from_ssz(block, SszTypes.BeaconBlock)
    end
  end

  @spec get_block_root_by_slot(SszTypes.slot()) ::
          {:ok, SszTypes.root()} | {:error, String.t()} | :not_found
  def get_block_root_by_slot(slot) do
    key = block_root_by_slot_key(slot)
    Db.get(key)
  end

  @spec get_block_by_slot(SszTypes.slot()) ::
          {:ok, SszTypes.BeaconBlock.t()} | {:error, String.t()} | :not_found
  def get_block_by_slot(slot) do
    # WARN: this will return the latest block received for the given slot
    with {:ok, root} <- get_block_root_by_slot(slot) do
      get_block(root)
    end
  end

  def stream_missing_blocks_desc do
    Stream.resource(&init_cursor/0, &prev_slot/1, &close_cursor/1)
    # TODO: we should remove this when we have a genesis block
    |> Stream.concat([-1])
    |> Stream.transform(nil, &get_missing/2)
  end

  defp init_cursor do
    max_key = block_root_by_slot_key(0xFFFFFFFFFFFFFFFF)

    with {:ok, it} <- Db.iterate_keys(),
         {:ok, _} <- Exleveldb.iterator_move(it, max_key) do
      it
    else
      # We'll just try again later
      {:error, :invalid_iterator} -> nil
    end
  end

  defp prev_slot(nil), do: {:halt, nil}

  defp prev_slot(it) do
    {:ok, prev_key} =
      Exleveldb.iterator_move(it, :prev)

    case prev_key do
      @blockslot_prefix <> <<key::64>> -> {[key], it}
      _ -> {:halt, it}
    end
  end

  defp close_cursor(nil), do: :ok
  defp close_cursor(it), do: :ok = Exleveldb.iterator_close(it)

  def get_missing(slot, nil), do: {[], slot}
  def get_missing(slot, prev), do: {(prev - 1)..(slot + 1)//-1, slot}

  defp block_key(root), do: Utils.get_key(@block_prefix, root)
  defp block_root_by_slot_key(slot), do: Utils.get_key(@blockslot_prefix, slot)
end
