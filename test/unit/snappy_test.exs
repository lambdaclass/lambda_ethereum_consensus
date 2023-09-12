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

  test "snappy block decompression" do
    expected =
      "E400000011766D0000000000000000000000000018F41F47CD8EBF7FF17CED045954D1894D24CEC72361696FEC121C6D3EF99510AF6B0300000000006FEFAA78066FBFE3763C971204CBAAB0E6BC14A9643A28900AF7DAB9353A2988B06B03000000000012E2B17EA473B5EA28338C129976BFDA58A3AA7244EF01B7456B1A8DEC2C72ABACFF3B742DDF85EF0CCE1C60394244C4EED37EBEB6E7BDF917CBDA90984F70B3DD4A1220B9D164DFFAB4521BB39CB5A10F82D4C910325DCE7899485EA39B29A02C2138B6A29A39F65FF453E233DBF7B4F49FC7B9BD53455EAA7411CFB3A3560700000000000000000000000000000800000000000000000000000000000000000000000000000000000000000080"

    got =
      "92021CE400000011766D002E01008818F41F47CD8EBF7FF17CED045954D1894D24CEC72361696FEC121C6D3EF99510AF6B03052F806FEFAA78066FBFE3763C971204CBAAB0E6BC14A9643A28900AF7DAB9353A2988B00D28F08112E2B17EA473B5EA28338C129976BFDA58A3AA7244EF01B7456B1A8DEC2C72ABACFF3B742DDF85EF0CCE1C60394244C4EED37EBEB6E7BDF917CBDA90984F70B3DD4A1220B9D164DFFAB4521BB39CB5A10F82D4C910325DCE7899485EA39B29A02C2138B6A29A39F65FF453E233DBF7B4F49FC7B9BD53455EAA7411CFB3A35607000005AF0D0100080D085A01000080"
      |> Base.decode16!()
      |> :snappyer.decompress()
      |> then(fn {:ok, b} -> Base.encode16(b) end)

    assert got == expected
  end
end
