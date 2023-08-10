defmodule SnappyTest do
  use ExUnit.Case
  use ExUnitProperties
  doctest Snappy

  def assert_snappy_decompress(compressed, uncompressed) do
    {:ok, ^uncompressed} =
      compressed
      |> Base.decode16!()
      |> Snappy.decompress()
  end

  test "decompress binary" do
    # Uncompressed chunks
    msg = "0011FF060000734E6150705901150000F1D17CFF0008000000000000FFFFFFFFFFFFFFFF0F"
    # status <> length <> ...
    "00" <> "11" <> compressed_payload = msg
    expected = Base.decode16!("0008000000000000FFFFFFFFFFFFFFFF0F")

    assert_snappy_decompress(compressed_payload, expected)

    msg = "0011FF060000734E6150705901150000CD11E7D53A03000000000000FFFFFFFFFFFFFFFF0F"
    "00" <> "11" <> compressed_payload = msg
    expected = Base.decode16!("3A03000000000000FFFFFFFFFFFFFFFF0F")

    assert_snappy_decompress(compressed_payload, expected)

    # Compressed chunks
    msg = "0011FF060000734E61507059000A0000B3A056EA1100003E0100"
    "00" <> "11" <> compressed_payload = msg
    expected = Base.decode16!("0000000000000000000000000000000000")

    assert_snappy_decompress(compressed_payload, expected)

    msg =
      "011CFF060000734E6150705900220000EF99F84B1C6C4661696C656420746F20756E636F6D7072657373206D657373616765"

    "01" <> "1C" <> compressed_payload = msg

    assert_snappy_decompress(
      compressed_payload,
      "Failed to uncompress message"
    )
  end

  test "compress binary" do
    expected = Base.decode16!("FF060000734E61507059000A0000B3A056EA1100003E0100")

    got =
      Snappy.compress(Base.decode16!("0000000000000000000000000000000000"))

    assert got == {:ok, expected}
  end

  property "compress(decompress(x)) == x" do
    check all(bin <- binary()) do
      assert {:ok, compressed} = Snappy.compress(bin)
      assert {:ok, decompressed} = Snappy.decompress(compressed)
      assert decompressed == bin
    end
  end
end
