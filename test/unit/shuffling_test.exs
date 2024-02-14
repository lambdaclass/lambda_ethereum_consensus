defmodule Unit.ShufflingTest do
  @moduledoc false

  use ExUnit.Case

  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Shuffling

  doctest LambdaEthereumConsensus.StateTransition.Shuffling

  test "Shuffling a whole list should be equivalent to shuffing each single item" do
    seed = 1..32 |> Enum.map(fn _ -> :rand.uniform(256) - 1 end) |> :erlang.iolist_to_binary()
    index_count = 100
    input = 0..(index_count - 1)

    shuffled = Shuffling.shuffle_list(Aja.Vector.new(input), seed)

    for index <- input do
      {:ok, new_index} = Misc.compute_shuffled_index(index, index_count, seed)
      assert Aja.Enum.at(shuffled, index) == new_index
    end
  end
end
