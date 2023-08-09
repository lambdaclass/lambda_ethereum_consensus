defmodule SnappyTest do
  use ExUnit.Case
  doctest Snappy

  test "decompress stream" do
    # Compressed chunks
    msg = Base.decode16!("0011FF060000734E61507059000A0000B3A056EA1100003E0100")
    <<0, 17, compressed_payload::binary>> = msg

    stream =
      Stream.unfold(compressed_payload, fn
        "" -> nil
        <<x, rest::binary>> -> {<<x>>, rest}
      end)

    expected = Base.decode16!("0000000000000000000000000000000000")

    got =
      stream
      |> Snappy.decompress()

    assert got == {:ok, expected}
  end
end
