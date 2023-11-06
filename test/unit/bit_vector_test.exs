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

  test "sets a single bit" do
    bv = BitVector.new(0b0000, 4)
    assert bv |> BitVector.set(0) == <<0b0001::4>>
    assert bv |> BitVector.set(1) == <<0b0010::4>>
    assert bv |> BitVector.set(2) == <<0b0100::4>>
    assert bv |> BitVector.set(3) == <<0b1000::4>>
  end

  test "clears a single bit" do
    bv = BitVector.new(0b1111, 4)
    assert bv |> BitVector.clear(0) == <<0b1110::4>>
    assert bv |> BitVector.clear(1) == <<0b1101::4>>
    assert bv |> BitVector.clear(2) == <<0b1011::4>>
    assert bv |> BitVector.clear(3) == <<0b0111::4>>
  end
end
