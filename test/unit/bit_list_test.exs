defmodule BitListTest do
  use ExUnit.Case
  alias LambdaEthereumConsensus.Utils.BitList

  describe "Sub-byte BitList" do
    test "build from binary" do
      assert BitList.new(<<0b10100000, 0b1011100, 0b1>>) == {<<0b1011100, 0b10100000>>, 16}
    end

    test "sets a single bit" do
      bl = BitList.new(<<0b10100000, 0b1011100, 0b1>>)
      assert bl |> BitList.set(0) == {<<0b1011100, 0b10100001>>, 16}
      assert bl |> BitList.set(1) == {<<0b1011100, 0b10100010>>, 16}
      assert bl |> BitList.set(2) == {<<0b1011100, 0b10100100>>, 16}
      assert bl |> BitList.set(3) == {<<0b1011100, 0b10101000>>, 16}
      assert bl |> BitList.set(4) == {<<0b1011100, 0b10110000>>, 16}
      assert bl |> BitList.set(5) == {<<0b1011100, 0b10100000>>, 16}
      assert bl |> BitList.set(6) == {<<0b1011100, 0b11100000>>, 16}
      assert bl |> BitList.set(7) == {<<0b1011100, 0b10100000>>, 16}
    end

    test "clears a single bit" do
      bl = BitList.new(<<0b10100000, 0b1011100, 0b1>>)
      assert bl |> BitList.clear(0) == {<<0b1011100, 0b10100000>>, 16}
      assert bl |> BitList.clear(1) == {<<0b1011100, 0b10100000>>, 16}
      assert bl |> BitList.clear(2) == {<<0b1011100, 0b10100000>>, 16}
      assert bl |> BitList.clear(3) == {<<0b1011100, 0b10100000>>, 16}
      assert bl |> BitList.clear(4) == {<<0b1011100, 0b10100000>>, 16}
      assert bl |> BitList.clear(5) == {<<0b1011100, 0b10000000>>, 16}
      assert bl |> BitList.clear(6) == {<<0b1011100, 0b10100000>>, 16}
      assert bl |> BitList.clear(7) == {<<0b1011100, 0b00100000>>, 16}
    end

    test "queries if a bit is set correctly using little-endian bit indexing" do
      bl = BitList.new(<<0b10100000, 0b1011100, 0b1>>)
      assert BitList.set?(bl, 0) == false
      assert BitList.set?(bl, 1) == false
      assert BitList.set?(bl, 2) == false
      assert BitList.set?(bl, 3) == false
      assert BitList.set?(bl, 4) == false
      assert BitList.set?(bl, 5) == true
      assert BitList.set?(bl, 6) == false
      assert BitList.set?(bl, 7) == true
    end
  end
end
