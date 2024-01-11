defmodule Types.StoreImpl.InMemory do
  @moduledoc """
  Store implementation that stores data in memory.
  """
  alias Types.BeaconBlock
  alias Types.SignedBeaconBlock

  @typep storage() :: %{
           blocks: %{Types.root() => BeaconBlock.t()},
           block_states: %{Types.root() => BeaconState.t()}
         }

  @empty_state %{blocks: %{}, block_states: %{}}

  def init, do: {__MODULE__, @empty_state}

  ## Blocks

  @spec store_block(storage(), Types.root(), SignedBeaconBlock.t()) :: storage()
  def store_block(%{blocks: blocks} = storage, block_root, %{message: block}),
    do: %{storage | blocks: Map.put(blocks, block_root, block)}

  @spec get_block(storage(), Types.root()) :: Types.BeaconBlock.t() | nil
  def get_block(%{blocks: blocks}, block_root), do: Map.get(blocks, block_root)

  @spec get_blocks(storage()) :: Enumerable.t(Types.BeaconBlock.t())
  def get_blocks(%{blocks: blocks}), do: blocks

  ## Block states

  @spec store_state(storage(), Types.root(), BeaconState.t()) :: storage()
  def store_state(%{block_states: states} = storage, block_root, state),
    do: %{storage | block_states: Map.put(states, block_root, state)}

  @spec get_state(storage(), Types.root()) :: BeaconState.t() | nil
  def get_state(%{block_states: states}, block_root), do: Map.get(states, block_root)
end
