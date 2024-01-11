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
end
