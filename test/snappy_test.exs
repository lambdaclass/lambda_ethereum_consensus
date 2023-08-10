defmodule SnappyTest do
  use ExUnit.Case
  doctest Snappy

  test "decompress stream" do
    # Compressed chunks
    msg =
      Base.decode16!(
        "011CFF060000734E6150705900220000EF99F84B1C6C4661696C656420746F20756E636F6D7072657373206D657373616765"
      )

    <<01, 28, compressed_payload::binary>> = msg

    stream =
      Stream.unfold(compressed_payload, fn
        "" -> nil
        <<x, rest::binary>> -> {<<x>>, rest}
      end)

    expected = "Failed to uncompress message"

    got =
      stream
      |> Snappy.decompress!()
      |> Enum.join()

    assert got == expected
  end
end
