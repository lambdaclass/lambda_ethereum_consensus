defmodule LambdaEthereumConsensus.Store.Blocks do
  @moduledoc false
  alias LambdaEthereumConsensus.Store.Blocks.DbCache
  alias LambdaEthereumConsensus.Store.Blocks.InMemory
  alias Types.SignedBeaconBlock

  @type t() :: DbCache.t() | InMemory.t()

  ##########################
  ### Constructors
  ##########################

  def persistent, do: DbCache.new()
  def in_memory, do: InMemory.new()

  ##########################
  ### Public API
  ##########################

  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  def store_block(%name{} = impl, block_root, signed_block) do
    name.store_block(impl, block_root, signed_block)
  end

  @spec get_block(t(), Types.root()) :: SignedBeaconBlock.t() | nil
  def get_block(%name{} = impl, block_root), do: name.get_block(impl, block_root)
end
