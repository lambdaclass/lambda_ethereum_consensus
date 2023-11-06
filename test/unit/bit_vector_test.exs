defmodule BitVectorTest do
  use ExUnit.Case
  alias LambdaEthereumConsensus.Utils.BitVector

  test "build from binary" do
    bv = BitVector.new(0b0110, 4)
    assert bv == <<6::4>>
  end
end
