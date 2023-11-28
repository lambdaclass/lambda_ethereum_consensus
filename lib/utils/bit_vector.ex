defmodule LambdaEthereumConsensus.Utils.BitVector do
  @moduledoc """
  Set of utilities to interact with bit vectors, represented as bitstrings.
  The vector is indexed with little endian bit notation. That is, the 0th bit
  is the less significant bit of the corresponding byte.
  """

  # The internal representation is a bitstring, but we could evaluate
  # turning it into an integer to use bitwise operations instead.
  @type t :: bitstring

  @doc """
  Creates a new bit_vector from an integer or a bitstring.
  """
  @spec new(integer, non_neg_integer) :: t
  def new(number, size) when is_integer(number), do: <<number::size(size)>>

  @spec new(bitstring, non_neg_integer) :: t
  def new(bitstring, size) when is_bitstring(bitstring) do
    <<_::size(bit_size(bitstring) - size), b::bitstring>> = bitstring
    b
  end

  @doc """
  True if a single bit is set to 1.
  Equivalent to bit_vector[index] == 1.
  """
  @spec set?(t, non_neg_integer) :: boolean
  def set?(bit_vector, index) do
    skip = bit_size(bit_vector) - index - 1
    match?(<<_::size(skip), 1::size(1), _::bitstring>>, bit_vector)
  end

  @doc """
  True if all bits in the specified range are set to 1.
  Equivalent to all(bit_vector[first..last]) in the specs.
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
  Equivalent to bit_vector[index] = 1.
  """
  @spec set(t, non_neg_integer) :: t
  def set(bit_vector, index) do
    skip = bit_size(bit_vector) - index - 1
    <<pre::bitstring-size(skip), _::size(1), rest::bitstring>> = bit_vector
    <<pre::bitstring, 1::1, rest::bitstring>>
  end

  @doc """
  Clears a bit (turns it to 0).
  Equivalent to bit_vector[index] = 0.
  """
  @spec clear(t, non_neg_integer) :: t
  def clear(bit_vector, index) do
    skip = bit_size(bit_vector) - index - 1
    <<pre::bitstring-size(skip), _::size(1), rest::bitstring>> = bit_vector
    <<pre::bitstring, 0::1, rest::bitstring>>
  end

  @doc """
  Shifts a vector n steps to higher indices. For example, using shift_higher(vector, 1) is
  equivalent in the specs to:
  1. vector[1:] = vector[:size-1]
  2. vector[0] = 0b0

  Internally, this is a left shift, due to the little-endian bit indexing.
  """
  @spec shift_higher(t, non_neg_integer()) :: t
  def shift_higher(bit_vector, steps) do
    <<_::size(steps), remaining::bitstring>> = bit_vector
    <<remaining::bitstring, 0::size(steps)>>
  end

  @doc """
  Shifts a vector n steps to the lower indices. For example, using left_shift(vector, 1) is
  equivalent in the specs to:
  1. vector[:size-1] = vector[1:]
  2. vector[size-1] = 0b0

  Internally, this is a right shift, due to the little-endian bit indexing.
  """
  @spec shift_lower(t, non_neg_integer) :: t
  def shift_lower(bit_vector, steps) do
    <<remaining::size(bit_size(bit_vector) - steps)-bitstring, _::bitstring>> = bit_vector
    <<0::size(steps), remaining::bitstring>>
  end
end
