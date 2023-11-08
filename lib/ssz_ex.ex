defmodule LambdaEthereumConsensus.SszEx do
  @moduledoc """
    SSZ library in Elixir
  """
  #################
  ### Public API
  #################
  def encode(value, {:int, size}), do: encode_int(value, size)
  def encode(value, :bool), do: encode_bool(value)

  def decode(binary, :bool), do: decode_bool(binary)
  def decode(binary, {:int, size}), do: decode_uint(binary, size)

  #################
  ### Private functions
  #################
  defp encode_int(value, size) when is_integer(value) do
    <<encoded::binary-size(div(size, 8)), _rest::binary>> =
      value
      |> :binary.encode_unsigned(:little)
      |> String.pad_trailing(div(size, 8), <<0>>)

    encoded
  end

  defp decode_uint(binary, size) do
    <<element::integer-size(size)-little, _rest::bitstring>> = binary
    element
  end

  defp encode_bool(true), do: "\x01"
  defp encode_bool(false), do: "\x00"

  defp decode_bool("\x01"), do: true
  defp decode_bool("\x00"), do: false
end
