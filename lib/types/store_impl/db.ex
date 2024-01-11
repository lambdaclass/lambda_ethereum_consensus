defmodule Types.StoreImpl.Db do
  @moduledoc """
  Store implementation that stores data in the database, uncached.
  """
  alias LambdaEthereumConsensus.Store.BlockStore
  alias LambdaEthereumConsensus.Store.StateStore
  alias Types.BeaconBlock
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  def init, do: __MODULE__

  ## Blocks

  @spec store_block(Types.root(), SignedBeaconBlock.t()) :: any()
  def store_block(block_root, signed_block),
    do: BlockStore.store_block(signed_block, block_root)

  @spec get_block(Types.root()) :: BeaconBlock.t() | nil
  def get_block(block_root) do
    case BlockStore.get_block(block_root) do
      {:ok, signed_block} -> signed_block.message
      _ -> nil
    end
  end

  @spec get_blocks() :: Enumerable.t(BeaconBlock.t())
  def get_blocks, do: BlockStore.stream_blocks()

  ## Block states

  @spec store_state(Types.root(), BeaconState.t()) :: any()
  def store_state(block_root, state), do: StateStore.store_state(state, block_root)

  @spec get_state(Types.root()) :: BeaconState.t() | nil
  def get_state(block_root) do
    case StateStore.get_state(block_root) do
      {:ok, state} -> state
      {:error, reason} -> raise "DB failed: #{inspect(reason)}"
      :not_found -> nil
    end
  end
end
