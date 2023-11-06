defmodule LambdaEthereumConsensus.Utils.BitVector do
  @moduledoc """
  Set of utilities to interact with bit vectors, represented as bitstrings.
  The vector is indexed with little endian bit notation. That is, the bit 0
  is the less significant 1.
  """

  # The internal representation is a bitstring, but we could evaluate
  # turning it into an integer to use bitwise operations instead.
  @type t :: bitstring

  @doc """
  Creates a new bit_vector from an integer or a bitstring.
  """
  @spec new(integer, non_neg_integer) :: t
  def new(number, s) when is_integer(number), do: <<number::size(s)>>

  def new(bitstring, s) when is_bitstring(bitstring) do
    <<_::size(bit_size(bitstring) - s), b::bitstring>> = bitstring
    b
  end

  @doc """
  True if a single bit is set to 1.
  """
  @spec set?(t, non_neg_integer) :: boolean
  def set?(bit_vector, index) do
    skip = bit_size(bit_vector) - index - 1
    match?(<<_::size(skip), 1::size(1), _::bitstring>>, bit_vector)
  end

  @doc """
  True if all bits in the specified range are set to 1.
  """
  @spec all?(t, Range.t()) :: boolean
  def all?(bit_vector, first..last) do
    skip = bit_size(bit_vector) - last
    range_size = last - first
    target = 2 ** range_size - 1
    match?(<<_::size(skip), ^target::size(range_size), _::bitstring>>, bit_vector)
  end

  @doc """
  Sets a bit (turns it to 1).
  """
  @spec set(t, non_neg_integer) :: t
  def set(bit_vector, index) do
    skip = bit_size(bit_vector) - index - 1
    <<pre::bitstring-size(skip), _::size(1), rest::bitstring>> = bit_vector
    <<pre::bitstring, 1::1, rest::bitstring>>
  end

  @doc """
  Clears a bit (turns it to 0).
  """
  @spec clear(t, non_neg_integer) :: t
  def clear(bit_vector, index) do
    skip = bit_size(bit_vector) - index - 1
    <<pre::bitstring-size(skip), _::size(1), rest::bitstring>> = bit_vector
    <<pre::bitstring, 0::1, rest::bitstring>>
  end
end
