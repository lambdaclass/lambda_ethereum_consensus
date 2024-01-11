defmodule Types.StoreImpl.Db do
  alias Types.SignedBeaconBlock

  @spec store_block(Types.root(), SignedBeaconBlock.t()) :: any()
  def store_block(block_root, signed_block),
    do: BlockStore.store_block(signed_block, block_root)
end
