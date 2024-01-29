defmodule LambdaEthereumConsensus.Utils.BitList do
  @moduledoc """
    Set of utilities to interact with BitList, represented as {bitstring, len}.
  """
  alias LambdaEthereumConsensus.Utils.BitField
  @type t :: {bitstring, integer()}
  @bits_per_byte 8

  @doc """
  Creates a new bit_list from bitstring.
  """
  @spec new(bitstring) :: t
  def new(bitstring) when is_bitstring(bitstring) do
    # Change the byte order from little endian to big endian (reverse bytes).
    num_bits = bit_size(bitstring)
    len = length_of_bitlist(bitstring)

    <<pre::integer-little-size(num_bits - 8), last_byte::integer-little-size(@bits_per_byte)>> =
      bitstring

    decoded = <<remove_trailing_bit(<<last_byte>>)::bitstring, pre::integer-size(num_bits - 8)>>
    {decoded, len}
  end

  @spec to_bytes(t) :: bitstring
  def to_bytes({bit_list, len}) do
    # Change the byte order from big endian to little endian (reverse bytes).
    r = rem(len, @bits_per_byte)

    <<pre::integer-size(r), post::integer-size(len - r)>> = bit_list

    <<post::integer-little-size(len - r), 1::integer-little-size(@bits_per_byte - r),
      pre::integer-little-size(r)>>
  end

  @doc """
  True if a single bit is set to 1.
  Equivalent to bit_list[index] == 1.
  """
  @spec set?(t, non_neg_integer) :: boolean
  def set?({bit_list, _}, index), do: BitField.set?(bit_list, index)

  @doc """
  Sets a bit (turns it to 1).
  Equivalent to bit_list[index] = 1.
  """
  @spec set(t, non_neg_integer) :: t
  def set({bit_list, len}, index), do: {BitField.set(bit_list, index), len}

  @doc """
  Clears a bit (turns it to 0).
  Equivalent to bit_list[index] = 0.
  """
  @spec clear(t, non_neg_integer) :: t
  def clear({bit_list, len}, index), do: {BitField.clear(bit_list, index), len}

  def length_of_bitlist(bitlist) when is_binary(bitlist) do
    bit_size = bit_size(bitlist)
    <<_::size(bit_size - 8), last_byte>> = bitlist
    bit_size - leading_zeros(<<last_byte>>) - 1
  end

  defp leading_zeros(<<1::1, _::7>>), do: 0
  defp leading_zeros(<<0::1, 1::1, _::6>>), do: 1
  defp leading_zeros(<<0::2, 1::1, _::5>>), do: 2
  defp leading_zeros(<<0::3, 1::1, _::4>>), do: 3
  defp leading_zeros(<<0::4, 1::1, _::3>>), do: 4
  defp leading_zeros(<<0::5, 1::1, _::2>>), do: 5
  defp leading_zeros(<<0::6, 1::1, _::1>>), do: 6
  defp leading_zeros(<<0::7, 1::1>>), do: 7
  defp leading_zeros(<<0::8>>), do: 8

  @spec remove_trailing_bit(binary()) :: bitstring()
  defp remove_trailing_bit(<<1::1, rest::7>>), do: <<rest::7>>
  defp remove_trailing_bit(<<0::1, 1::1, rest::6>>), do: <<rest::6>>
  defp remove_trailing_bit(<<0::2, 1::1, rest::5>>), do: <<rest::5>>
  defp remove_trailing_bit(<<0::3, 1::1, rest::4>>), do: <<rest::4>>
  defp remove_trailing_bit(<<0::4, 1::1, rest::3>>), do: <<rest::3>>
  defp remove_trailing_bit(<<0::5, 1::1, rest::2>>), do: <<rest::2>>
  defp remove_trailing_bit(<<0::6, 1::1, rest::1>>), do: <<rest::1>>
  defp remove_trailing_bit(<<0::7, 1::1>>), do: <<0::0>>
  defp remove_trailing_bit(<<0::8>>), do: <<0::0>>
end
