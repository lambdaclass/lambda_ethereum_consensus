defmodule LambdaEthereumConsensus.Store.BlockStore do
  @moduledoc """
  Storage and retrieval of blocks.
  """

  @block_prefix "block"
  @slothash_prefix "slothash"

  @spec store_block(SszTypes.BeaconBlock.t()) :: :ok
  def store_block(%SszTypes.BeaconBlock{} = block) do
    {:ok, block_root} = Ssz.hash_tree_root(block)
    {:ok, encoded_block} = Ssz.to_ssz(block)

    key = get_key(@block_prefix, block_root)
    LambdaEthereumConsensus.Store.Db.put(key, encoded_block)
    slothash_key = get_key(@slothash_prefix, block.slot)
    LambdaEthereumConsensus.Store.Db.put(slothash_key, block_root)
  end

  @spec get_block(SszTypes.root()) :: {:ok, struct()} | {:error, String.t()} | :not_found
  def get_block(block_root) do
    key = get_key(@block_prefix, block_root)

    with {:ok, block} <- LambdaEthereumConsensus.Store.Db.get(key) do
      Ssz.from_ssz(block, SszTypes.BeaconBlock)
    end
  end

  @spec get_block_root_by_slot(SszTypes.slot()) ::
          {:ok, SszTypes.root()} | {:error, String.t()} | :not_found
  def get_block_root_by_slot(slot) do
    key = get_key(@slothash_prefix, slot)
    LambdaEthereumConsensus.Store.Db.get(key)
  end

  @spec get_block_by_slot(SszTypes.slot()) ::
          {:ok, SszTypes.BeaconBlock.t()} | {:error, String.t()} | :not_found
  def get_block_by_slot(slot) do
    with {:ok, root} <- get_block_root_by_slot(slot) do
      get_block(root)
    end
  end

  defp get_key(prefix, suffix) when is_integer(suffix) do
    prefix <> :binary.encode_unsigned(suffix)
  end

  defp get_key(prefix, suffix) when is_binary(suffix) do
    prefix <> suffix
  end
end
