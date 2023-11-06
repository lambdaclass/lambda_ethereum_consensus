defmodule BitVectorTest do
  use ExUnit.Case
  alias LambdaEthereumConsensus.Utils.BitVector

  test "build from integer" do
    assert BitVector.new(0b1110, 4) == <<14::4>>
  end

  test "build from binary" do
    assert BitVector.new(<<0b00001110>>, 4) == <<14::4>>
  end

  test "queries if a bit is set correctly using little-endian bit indexing" do
    bv = BitVector.new(0b1110, 4)
    assert BitVector.set?(bv, 0) == false
    assert BitVector.set?(bv, 1) == true
    assert BitVector.set?(bv, 2) == true
    assert BitVector.set?(bv, 3) == true
  end

  test "queries if a range of bits is all set" do
    bv = BitVector.new(0b1110, 4)

    # 1 bit ranges
    assert not BitVector.all?(bv, 0..1)
    assert BitVector.all?(bv, 1..2)
    assert BitVector.all?(bv, 2..3)
    assert BitVector.all?(bv, 3..4)

    # 2 bit ranges
    assert not BitVector.all?(bv, 0..2)
    assert BitVector.all?(bv, 1..3)
    assert BitVector.all?(bv, 2..4)

    # 3 bit ranges
    assert not BitVector.all?(bv, 0..3)
    assert BitVector.all?(bv, 1..4)

    # 4 bit range
    assert not BitVector.all?(bv, 0..4)
  end
end
