defmodule LambdaEthereumConsensus.P2P.Utils do
  @moduledoc """
  Functions for encoding and decoding requests and responses.
  """
  import Bitwise

  @spec encode_varint(integer()) :: binary()
  def encode_varint(int) do
    # PERF: use IO lists
    Protobuf.Wire.Varint.encode(int)
    |> IO.iodata_to_binary()
  end

  @spec decode_varint(binary()) :: {non_neg_integer(), binary()}
  # PERF: use `Protobuf.Wire.Varint.defdecoderp` macro for this
  def decode_varint(bin), do: decode_varint(bin, 0, 0)

  defp decode_varint("", acc, _), do: {acc, ""}

  defp decode_varint(<<0::1, int::7, rest::binary>>, acc, shift) do
    {acc + (int <<< shift), rest}
  end

  defp decode_varint(<<1::1, int::7, rest::binary>>, acc, shift) do
    decode_varint(rest, acc + (int <<< shift), shift + 7)
  end
end
