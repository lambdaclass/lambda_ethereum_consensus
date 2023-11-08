defmodule Unit.SSZExTest do
  alias LambdaEthereumConsensus.SszEx
  use ExUnit.Case

  def assert_roundtrip(hex_serialized, deserialized, schema) do
    serialized = Base.decode16!(hex_serialized)
    assert ^serialized = SszEx.encode(deserialized, schema)
    assert deserialized === SszEx.decode(serialized, schema)
  end

  test "serialize and deserialize uint" do
    assert_roundtrip("05", 5, {:int, 8})
    assert_roundtrip("0500", 5, {:int, 16})
    assert_roundtrip("05000000", 5, {:int, 32})
    assert_roundtrip("0500000000000000", 5, {:int, 64})

    assert_roundtrip("63", 99, {:int, 8})
    assert_roundtrip("6300", 99, {:int, 16})
    assert_roundtrip("63000000", 99, {:int, 32})
    assert_roundtrip("6300000000000000", 99, {:int, 64})
  end

  test "serialize and deserialize bool" do
    assert_roundtrip("01", true, :bool)
    assert_roundtrip("00", false, :bool)
  end
end
