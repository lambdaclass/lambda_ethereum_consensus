defmodule BitVectorTest do
  use ExUnit.Case
  alias LambdaEthereumConsensus.Utils.BitVector

  test "build from binary" do
    bv = BitVector.new(0b1110, 4)
    assert bv == <<14::4>>
  end

  test "queries if a bit is set correctly using little-endian bit indexing" do
    bv = BitVector.new(0b1110, 4)
    assert BitVector.set?(bv, 0) == false
    assert BitVector.set?(bv, 1) == true
    assert BitVector.set?(bv, 2) == true
    assert BitVector.set?(bv, 3) == true
  end
end
