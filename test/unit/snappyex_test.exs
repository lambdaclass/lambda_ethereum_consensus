defmodule Unit.SnappyExTest do
  use ExUnit.Case
  use ExUnitProperties
  doctest SnappyEx

  def assert_snappy_decompress(compressed, uncompressed) do
    assert {:ok, ^uncompressed} = compressed |> Base.decode16!() |> SnappyEx.decompress()
  end

  test "test valid stream identifier" do
    # stream identier chunk
    msg = "0011FF060000734E61507059"

    # status <> length <> ...
    "00" <> "11" <> payload = msg
    expected = Base.decode16!("")

    assert_snappy_decompress(payload, expected)
  end

  test "test uncompressed stream" do
    # Uncompressed chunks
    msg = "0011FF060000734E6150705901150000F1D17CFF0008000000000000FFFFFFFFFFFFFFFF0F"

    # status <> length <> ...
    "00" <> "11" <> payload = msg
    expected = Base.decode16!("0008000000000000FFFFFFFFFFFFFFFF0F")

    assert_snappy_decompress(payload, expected)

    msg = "0011FF060000734E6150705901150000CD11E7D53A03000000000000FFFFFFFFFFFFFFFF0F"
    "00" <> "11" <> compressed_payload = msg
    expected = Base.decode16!("3A03000000000000FFFFFFFFFFFFFFFF0F")

    assert_snappy_decompress(compressed_payload, expected)
  end

  test "test compressed stream" do
    # Compressed chunks
    msg = "0011FF060000734E61507059000A0000B3A056EA1100003E0100"
    "00" <> "11" <> compressed_payload = msg
    expected = Base.decode16!("0000000000000000000000000000000000")

    assert_snappy_decompress(compressed_payload, expected)
  end

  test "decompress Ping responses" do
    for {msg, expected} <- [
          {"0008FF060000734E61507059010C0000B18525A04300000000000000", "4300000000000000"},
          {"0008FF060000734E61507059010C00000175DE410100000000000000", "0100000000000000"},
          {"0008FF060000734E61507059010C0000EAB2043E0500000000000000", "0500000000000000"},
          {"0008FF060000734E61507059010C0000290398070000000000000000", "0000000000000000"}
        ] do
      "00" <> "08" <> compressed_payload = msg
      expected = Base.decode16!(expected)

      assert_snappy_decompress(compressed_payload, expected)
    end

    # Error response
    msg =
      "011CFF060000734E6150705900220000EF99F84B1C6C4661696C656420746F20756E636F6D7072657373206D657373616765"

    "01" <> "1C" <> compressed_payload = msg

    assert_snappy_decompress(compressed_payload, "Failed to uncompress message")
  end
end
