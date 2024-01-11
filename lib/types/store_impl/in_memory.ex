defmodule Types.StoreImpl.InMemory do
  alias Types.BeaconBlock
  alias Types.SignedBeaconBlock

  @typep state() :: %{
           blocks: %{Types.root() => BeaconBlock.t()},
           block_states: %{Types.root() => BeaconState.t()}
         }

  @spec store_block(state(), Types.root(), SignedBeaconBlock.t()) :: state()
  def store_block(%{blocks: blocks} = state, block_root, %{message: block}) do
    blocks
    |> Map.put(block_root, block)
    |> then(&%{state | blocks: &1})
  end

  @spec get_block(state(), Types.root()) :: Types.BeaconBlock.t() | nil
  def get_block(%{blocks: blocks}, block_root), do: Map.get(blocks, block_root)

  @spec get_blocks(state()) :: Enumerable.t(Types.BeaconBlock.t())
  def get_blocks(%{blocks: blocks}), do: blocks
end
