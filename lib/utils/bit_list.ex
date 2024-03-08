defmodule LambdaEthereumConsensus.Utils.BitList do
  @moduledoc """
  Set of utilities to interact with BitList, represented as a bitstring.
  """
  alias LambdaEthereumConsensus.Utils.BitField
  @type t :: bitstring
  @bits_per_byte 8
  @sentinel_bit 1
  @bits_in_sentinel_bit 1

  @doc """
  Creates a new bit_list with the given size.
  """
  @spec default(non_neg_integer) :: t
  def default(size), do: <<0::size(size)>>

  @doc """
  Creates a new bit_list from bitstring.
  """
  @spec new(bitstring) :: t
  def new(bitstring) when is_bitstring(bitstring) do
    # Change the byte order from little endian to big endian (reverse bytes).
    num_bits = bit_size(bitstring)

    <<pre::integer-little-size(num_bits - @bits_per_byte),
      last_byte::integer-little-size(@bits_per_byte)>> =
      bitstring

    <<remove_trailing_bit(<<last_byte>>)::bitstring,
      pre::integer-size(num_bits - @bits_per_byte)>>
  end

  @spec to_bytes(t) :: bitstring
  def to_bytes(bit_list) do
    # Change the byte order from big endian to little endian (reverse bytes).
    len = bit_size(bit_list)
    r = rem(len, @bits_per_byte)

    <<pre::integer-size(r), post::integer-size(len - r)>> = bit_list

    <<post::integer-little-size(len - r), @sentinel_bit::integer-little-size(@bits_per_byte - r),
      pre::integer-little-size(r)>>
  end

  @spec to_packed_bytes(t) :: bitstring
  def to_packed_bytes(bit_list) do
    # Change the byte order from big endian to little endian (reverse bytes).
    len = bit_size(bit_list)
    r = rem(len, @bits_per_byte)

    <<pre::integer-size(r), post::integer-size(len - r)>> = bit_list

    <<post::integer-little-size(len - r), 0::integer-little-size(@bits_per_byte - r),
      pre::integer-little-size(r)>>
  end

  @doc """
  True if a single bit is set to 1.
  Equivalent to bit_list[index] == 1.
  """
  @spec set?(t, non_neg_integer) :: boolean
  def set?(bit_list, index), do: BitField.set?(bit_list, index)

  @doc """
  Sets a bit (turns it to 1).
  Equivalent to bit_list[index] = 1.
  """
  @spec set(t, non_neg_integer) :: t
  def set(bit_list, index), do: BitField.set(bit_list, index)

  @doc """
  Clears a bit (turns it to 0).
  Equivalent to bit_list[index] = 0.
  """
  @spec clear(t, non_neg_integer) :: t
  def clear(bit_list, index), do: BitField.clear(bit_list, index)

  @doc """
  Calculates the length of the bit_list.
  """
  @spec length(t) :: non_neg_integer()
  def length(bit_list), do: bit_size(bit_list)

  @spec remove_trailing_bit(binary()) :: bitstring()
  defp remove_trailing_bit(<<@sentinel_bit::@bits_in_sentinel_bit, rest::7>>), do: <<rest::7>>

  defp remove_trailing_bit(<<0::1, @sentinel_bit::@bits_in_sentinel_bit, rest::6>>),
    do: <<rest::6>>

  defp remove_trailing_bit(<<0::2, @sentinel_bit::@bits_in_sentinel_bit, rest::5>>),
    do: <<rest::5>>

  defp remove_trailing_bit(<<0::3, @sentinel_bit::@bits_in_sentinel_bit, rest::4>>),
    do: <<rest::4>>

  defp remove_trailing_bit(<<0::4, @sentinel_bit::@bits_in_sentinel_bit, rest::3>>),
    do: <<rest::3>>

  defp remove_trailing_bit(<<0::5, @sentinel_bit::@bits_in_sentinel_bit, rest::2>>),
    do: <<rest::2>>

  defp remove_trailing_bit(<<0::6, @sentinel_bit::@bits_in_sentinel_bit, rest::1>>),
    do: <<rest::1>>

  defp remove_trailing_bit(<<0::7, @sentinel_bit::@bits_in_sentinel_bit>>), do: <<0::0>>
  defp remove_trailing_bit(<<0::8>>), do: <<0::0>>
end
