defmodule Types.StoreImpl.InMemory do
  @moduledoc """
  Store implementation that stores data in memory.
  """

  alias Types.BeaconBlock
  alias Types.BeaconState

  defstruct blocks: %{}, block_states: %{}

  @type t() :: %{
          blocks: %{Types.root() => BeaconBlock.t()},
          block_states: %{Types.root() => BeaconState.t()}
        }

  defimpl Types.StoreImpl, for: __MODULE__ do
    ## Blocks
    def store_block(%{blocks: blocks} = storage, block_root, %{message: block}),
      do: %{storage | blocks: Map.put(blocks, block_root, block)}

    def get_block(%{blocks: blocks}, block_root), do: Map.get(blocks, block_root)

    def get_blocks(%{blocks: blocks}), do: blocks

    ## Block states
    def store_state(%{block_states: states} = storage, block_root, state),
      do: %{storage | block_states: Map.put(states, block_root, state)}

    def get_state(%{block_states: states}, block_root), do: Map.get(states, block_root)
  end
end
