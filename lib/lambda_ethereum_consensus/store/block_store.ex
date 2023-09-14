defmodule LambdaEthereumConsensus.Store.BlockStore do
  @moduledoc """
  Storage and retrieval of blocks.
  """

  @prefix "block"

  @spec store_block(SszTypes.BeaconBlock.t()) :: any
  def store_block(%SszTypes.BeaconBlock{} = block) do
    {:ok, block_root} = Ssz.hash_tree_root(block)
    {:ok, encoded_block} = Ssz.to_ssz(block)

    key = @prefix <> block_root
    LambdaEthereumConsensus.Store.Db.put(key, encoded_block)
  end

  @spec get_block(SszTypes.root()) :: {:ok, struct()} | {:error, String.t()} | :not_found
  def get_block(block_root) do
    key = @prefix <> block_root

    case LambdaEthereumConsensus.Store.Db.get(key) do
      :not_found ->
        :not_found

      {:ok, block} ->
        Ssz.from_ssz(block, SszTypes.BeaconBlock)
    end
  end
end
