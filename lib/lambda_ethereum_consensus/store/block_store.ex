defmodule LambdaEthereumConsensus.Store.BlockStore do
  @moduledoc """
  Storage and retrieval of blocks.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils

  @block_prefix "block"
  @slot_prefix "slot"

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

  defp block_key(root), do: Utils.get_key(@block_prefix, root)
  defp block_root_by_slot_key(slot), do: Utils.get_key(@block_prefix <> @slot_prefix, slot)
end
