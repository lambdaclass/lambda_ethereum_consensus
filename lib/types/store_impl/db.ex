defmodule Types.StoreImpl.Db do
  alias LambdaEthereumConsensus.Store.BlockStore
  alias Types.SignedBeaconBlock

  @spec store_block(Types.root(), SignedBeaconBlock.t()) :: any()
  def store_block(block_root, signed_block),
    do: BlockStore.store_block(signed_block, block_root)

  @spec get_block(Types.root()) :: Types.BeaconBlock.t() | nil
  def get_block(block_root) do
    case BlockStore.get_block(block_root) do
      {:ok, signed_block} -> signed_block.message
      _ -> nil
    end
  end

  @spec get_blocks() :: Enumerable.t(Types.BeaconBlock.t())
  def get_blocks, do: BlockStore.stream_blocks()
end
