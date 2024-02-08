defmodule Unit.SnappyExTest do
  use ExUnit.Case
  use ExUnitProperties
  doctest SnappyEx

  @empty_stream <<0xFF, 6::little-size(24)>> <> "sNaPpY"

  defp assert_snappy_decompress(compressed, uncompressed) do
    assert compressed |> Base.decode16!() |> SnappyEx.decompress() ==
             {:ok, Base.decode16!(uncompressed)}
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

  test "decompress GetMetadata response uncompressed 0" do
    assert_snappy_decompress(
      "FF060000734E6150705901150000F1D17CFF0008000000000000FFFFFFFFFFFFFFFF0F",
      "0008000000000000FFFFFFFFFFFFFFFF0F"
    )
  end

  test "decompress GetMetadata response uncompressed 1" do
    assert_snappy_decompress(
      "FF060000734E6150705901150000CD11E7D53A03000000000000FFFFFFFFFFFFFFFF0F",
      "3A03000000000000FFFFFFFFFFFFFFFF0F"
    )
  end

  test "decompress GetMetadata response compressed" do
    assert_snappy_decompress(
      "FF060000734E61507059000A0000B3A056EA1100003E0100",
      "0000000000000000000000000000000000"
    )
  end

  test "decompress Ping response 0" do
    assert_snappy_decompress(
      "FF060000734E61507059010C0000B18525A04300000000000000",
      "4300000000000000"
    )
  end

  test "decompress Ping response 1" do
    assert_snappy_decompress(
      "FF060000734E61507059010C00000175DE410100000000000000",
      "0100000000000000"
    )
  end

  test "decompress Ping response 2" do
    assert_snappy_decompress(
      "FF060000734E61507059010C0000EAB2043E0500000000000000",
      "0500000000000000"
    )
  end

  test "decompress Ping response 3" do
    assert_snappy_decompress(
      "FF060000734E61507059010C0000290398070000000000000000",
      "0000000000000000"
    )
  end

  test "decompress error response" do
    assert_snappy_decompress(
      "FF060000734E6150705900220000EF99F84B1C6C4661696C656420746F20756E636F6D7072657373206D657373616765",
      Base.encode16("Failed to uncompress message")
    )
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
