defmodule Unit.SSZExTest do
  alias LambdaEthereumConsensus.SszEx
  use ExUnit.Case

  def assert_roundtrip(serialized, deserialized, schema) do
    assert {:ok, ^serialized} = SszEx.encode(deserialized, schema)
    assert {:ok, deserialized} === SszEx.decode(serialized, schema)
  end

  test "serialize and deserialize uint" do
    assert_roundtrip(<<5>>, 5, {:int, 8})
    assert_roundtrip(<<5, 0>>, 5, {:int, 16})
    assert_roundtrip(<<5, 0, 0, 0>>, 5, {:int, 32})
    assert_roundtrip(<<5, 0, 0, 0, 0, 0, 0, 0>>, 5, {:int, 64})

    assert_roundtrip(<<20, 1>>, 276, {:int, 16})
    assert_roundtrip(<<20, 1, 0, 0>>, 276, {:int, 32})
    assert_roundtrip(<<20, 1, 0, 0, 0, 0, 0, 0>>, 276, {:int, 64})
  end

  test "serialize and deserialize bool" do
    assert_roundtrip(<<1>>, true, :bool)
    assert_roundtrip(<<0>>, false, :bool)
  end

  test "serialize and deserialize list" do
    assert_roundtrip(<<1, 1, 0>>, [true, true, false], {:list, :bool, 3})

    assert_roundtrip(
      <<230, 0, 0, 0, 124, 1, 0, 0, 11, 2, 0, 0>>,
      [230, 380, 523],
      {:list, {:int, 32}, 3}
    )

    variable_list = [[5, 6], [7, 8], [9, 10]]
    encoded_variable_list = <<12, 0, 0, 0, 14, 0, 0, 0, 16, 0, 0, 0, 5, 6, 7, 8, 9, 10>>
    assert_roundtrip(encoded_variable_list, variable_list, {:list, {:list, {:int, 8}, 2}, 3})

    variable_list = [[380, 6], [480, 8], [580, 10]]

    encoded_variable_list =
      <<12, 0, 0, 0, 28, 0, 0, 0, 44, 0, 0, 0, 124, 1, 0, 0, 0, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0,
        224, 1, 0, 0, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 0, 68, 2, 0, 0, 0, 0, 0, 0, 10, 0, 0, 0, 0,
        0, 0, 0>>

    assert_roundtrip(encoded_variable_list, variable_list, {:list, {:list, {:int, 64}, 2}, 3})
  end
end
