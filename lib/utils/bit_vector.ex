defmodule LambdaEthereumConsensus.Utils.BitVector do
  @moduledoc """
  Set of utilities to interact with bit vectors, represented as bitstrings.
  SSZ BitVectors use little-endian-bit-indexing. That means that if we think
  the vector as representing a number, the bit indexed at 0 is the numbers
  least significant bit. If we're representing the number 11, (in binary, 1011, or 0xA),
  the bit vector is, conceptually, [1, 1, 0, 1]. That means that:
  - bv = BitVector(11)
  - set?(bv, 1) == 1
  - set?(bv, 2) == 0

  However, when serialized using SSZ, the vectors use the little endian byte notation
  and are 0 padded. So for instance, for the same number 11, it's serialized as
  1011. Little endian bit notation and little endian byte notation are similar,
  but each of the bytes is individually reversed.

  ## Implementation details

  From the user point of view, the internal representation of this module is not important
  We document it here for possible refactors.

  One of the simplest ways to represent a bitvector in elixir is a bitstring, as it holds
  the exact amount of bits the bitvector would. This has many great properties, but is
  specially important for shifting, and it saves us from representing the length separately.

  With little-endian byte order we can't use bitstrings, as we'll need full bytes, so we need
  to either use little-endian bit order or big-endian order. We are choosing the latter as an
  internal representation as it's very simple to only swap bytes instead of bits.

  This means that when "new" is called over a bytestring, it is assumed that it's in little
  endian representation.
  """

  # The internal representation is a bitstring, but we could evaluate
  # turning it into an integer to use bitwise operations instead.
  @type t :: bitstring

  defguard is_bitvector(value) when is_bitstring(value)

  defguard bit_vector_size(value) when bit_size(value)

  @doc """
  Creates a new zeroed bit_vector with the given size.
  """
  @spec new(non_neg_integer) :: t
  def new(size) when size >= 0, do: <<0::size(size)>>

  @doc """
  Creates a new bit_vector from an integer or a bitstring.
  """
  @spec new(integer, non_neg_integer) :: t
  def new(number, size) when is_integer(number), do: <<number::size(size)>>

  @spec new(bitstring, non_neg_integer) :: t
  def new(bitstring, size) when is_bitstring(bitstring) do
    # Change the byte order from little endian to big endian (reverse bytes).
    encoded_size = bit_size(bitstring)
    <<num::integer-little-size(encoded_size)>> = bitstring
    <<num::integer-size(size)>>
  end

  @spec to_bytes(t) :: bitstring
  def to_bytes(bit_vector) do
    # Change the byte order from big endian to little endian (reverse bytes).
    <<num::integer-size(bit_size(bit_vector))>> = bit_vector
    <<num::integer-little-size(byte_size(bit_vector) * 8)>>
  end

  @doc """
  Turns the bit_vector into an integer.
  """
  @spec to_integer(t) :: non_neg_integer()
  def to_integer(bit_vector) do
    <<int::unsigned-size(bit_size(bit_vector))>> = bit_vector
    int
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

  @doc """
  Returns the amount of bits set.
  """
  @spec count(t) :: non_neg_integer()
  def count(bit_vector), do: for(<<bit::1 <- bit_vector>>, do: bit) |> Enum.sum()
end
