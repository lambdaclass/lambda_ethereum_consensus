defmodule LambdaEthereumConsensus.Store.Blocks do
  @moduledoc false
  alias LambdaEthereumConsensus.Store.Blocks.DbCache

  ##########################
  ### Constructors
  ##########################

  def persistent, do: DbCache.new()
  def in_memory, do: DbCache.new()

  ##########################
  ### Public API
  ##########################

  @spec store_block(DbCache.t(), Types.root(), SignedBeaconBlock.t()) :: :ok
  def store_block(%name{}, block_root, signed_block) do
    name.store_block(block_root, signed_block)
  end

  @spec get_block(DbCache.t(), Types.root()) :: SignedBeaconBlock.t() | nil
  def get_block(%name{}, block_root), do: name.get_block(block_root)
end
