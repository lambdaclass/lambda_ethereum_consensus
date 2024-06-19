defmodule Unit.BitFieldTest do
  use ExUnit.Case
  alias LambdaEthereumConsensus.Utils.BitField

  test "bitwise OR with sizes multiple of 8" do
    assert BitField.bitwise_or(<<0b0100_0001::size(8)>>, <<0b0000_0010::size(8)>>) ==
             <<0b0100_0011::size(8)>>

    assert BitField.bitwise_or(<<0b1010_1001::size(8)>>, <<0b0000_0010::size(8)>>) ==
             <<0b1010_1011::size(8)>>

    assert BitField.bitwise_or(<<0b0000000000000000::size(16)>>, <<0b1111111111111111::size(16)>>) ==
             <<0b1111111111111111::size(16)>>

    assert BitField.bitwise_or(<<0b1100110011001100::size(16)>>, <<0b0011001100110011::size(16)>>) ==
             <<0b1111111111111111::size(16)>>
  end

  test "bitwise OR with sizes not multiple of 8" do
    assert BitField.bitwise_or(<<0b101::size(3)>>, <<0b010::size(3)>>) == <<0b111::size(3)>>
    assert BitField.bitwise_or(<<0b1111::size(7)>>, <<0b0001::size(7)>>) == <<0b1111::size(7)>>

    assert BitField.bitwise_or(<<0b1010101010101::size(13)>>, <<0b0101010101010::size(13)>>) ==
             <<0b1111111111111::size(13)>>

    assert BitField.bitwise_or(<<0b1111000000001::size(13)>>, <<0b0000111111110::size(13)>>) ==
             <<0b1111111111111::size(13)>>
  end

  test "bitwise OR of all-zero and all-one bitfields" do
    assert BitField.bitwise_or(<<0::size(8)>>, <<255::size(8)>>) == <<255::size(8)>>
    assert BitField.bitwise_or(<<0::size(4)>>, <<15::size(4)>>) == <<15::size(4)>>
  end

  test "bitwise OR of same bitfields" do
    assert BitField.bitwise_or(<<0b1010::size(4)>>, <<0b1010::size(4)>>) == <<0b1010::size(4)>>
    assert BitField.bitwise_or(<<0b1111::size(4)>>, <<0b1111::size(4)>>) == <<0b1111::size(4)>>
  end

  test "bitwise OR with empty bitfields" do
    assert BitField.bitwise_or(<<>>, <<>>) == <<>>
  end
end
