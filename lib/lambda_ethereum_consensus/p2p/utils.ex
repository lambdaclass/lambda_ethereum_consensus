defmodule LambdaEthereumConsensus.P2P.Utils do
  @moduledoc """
  Functions for encoding and decoding requests and responses.
  """
  import Bitwise

  def encode_varint(int) do
    int
    |> Stream.unfold(&encode_varint_helper/1)
    |> Enum.join()
  end

  defp encode_varint_helper(nil), do: nil

  defp encode_varint_helper(x) when x >= 128 do
    {<<1::1, x::7>>, x >>> 7}
  end

  defp encode_varint_helper(x) when x < 128 do
    {<<0::1, x::7>>, nil}
  end

  def decode_varint(bin), do: decode_varint(bin, 0, 0)

  defp decode_varint(<<0::1, int::7, rest::binary>>, acc, shift) do
    {acc + (int <<< shift), rest}
  end

  defp decode_varint(<<1::1, int::7, rest::binary>>, acc, shift) do
    decode_varint(rest, acc + (int <<< shift), shift + 7)
  end
end
