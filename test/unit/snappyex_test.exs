defmodule Unit.SnappyExTest do
  use ExUnit.Case
  use ExUnitProperties
  doctest SnappyEx

  @empty_stream <<0xFF, 6::little-size(24)>> <> "sNaPpY"

  def assert_snappy_decompress(compressed, uncompressed) do
    assert compressed |> Base.decode16!() |> SnappyEx.decompress() == {:ok, uncompressed}
  end

  test "empty stream w/o stream identifier" do
    assert {:error, _} = SnappyEx.decompress("")
  end

  test "empty stream w/ stream identifier" do
    assert {:ok, ""} = SnappyEx.decompress(@empty_stream)
  end

  test "uncompressed stream" do
    data = "some uncompressed data"
    checksum = <<SnappyEx.compute_checksum(data)::little-size(32)>>

    size = byte_size(data) + byte_size(checksum)

    header = <<0x01, size::little-size(24)>>
    stream = Enum.join([@empty_stream, header, checksum, data])

    assert SnappyEx.decompress(stream) == {:ok, data}
  end

  test "compressed stream" do
    data = "some compressed data"
    checksum = <<SnappyEx.compute_checksum(data)::little-size(32)>>

    {:ok, compressed_data} = :snappyer.compress(data)
    size = byte_size(compressed_data) + byte_size(checksum)

    header = <<0x00, size::little-size(24)>>
    stream = Enum.join([@empty_stream, header, checksum, compressed_data])

    assert SnappyEx.decompress(stream) == {:ok, data}
  end

  test "decompress GetMetadata responses" do
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

  property "SnappyEx == Snappy: random stream" do
    check all(stream <- binary(min_length: 1)) do
      expected = Snappy.decompress(stream)

      case SnappyEx.decompress(stream) do
        {:ok, result} -> assert expected == {:ok, result}
        {:error, reason} -> assert {:error, _} = expected, reason
      end
    end
  end

  property "SnappyEx == Snappy: random valid stream" do
    check all(payload <- binary(min_length: 1)) do
      {:ok, stream} = Snappy.compress(payload)

      assert SnappyEx.decompress(stream) == {:ok, payload}
    end
  end
end
