defmodule LambdaEthereumConsensus.Utils.BitField do
  @moduledoc """
  Internal representation used by BitList (after trailling bit remove) and BitVector
  """

  @type t :: bitstring

  @doc """
  True if a single bit is set to 1.
  Equivalent to bit_field[index] == 1.
  """
  @spec set?(binary, non_neg_integer) :: boolean
  def set?(bit_field, index) do
    skip = bit_size(bit_field) - index - 1
    match?(<<_::size(skip), 1::size(1), _::bitstring>>, bit_field)
  end

  @doc """
  True if all bits in the specified range are set to 1.
  Equivalent to all(bit_field[first..last]) in the specs.
  """
  @spec all?(t, Range.t()) :: boolean
  def all?(bit_field, first..last) do
    skip = bit_size(bit_field) - last
    range_size = last - first
    target = 2 ** range_size - 1
    match?(<<_::size(skip), ^target::size(range_size), _::bitstring>>, bit_field)
  end

  @doc """
  Sets a bit (turns it to 1).
  Equivalent to bit_field[index] = 1.
  """
  @spec set(t, non_neg_integer) :: t
  def set(bit_field, index) do
    skip = bit_size(bit_field) - index - 1
    <<pre::bitstring-size(skip), _::size(1), rest::bitstring>> = bit_field
    <<pre::bitstring, 1::1, rest::bitstring>>
  end

  @doc """
  Clears a bit (turns it to 0).
  Equivalent to bit_field[index] = 0.
  """
  @spec clear(t, non_neg_integer) :: t
  def clear(bit_field, index) do
    skip = bit_size(bit_field) - index - 1
    <<pre::bitstring-size(skip), _::size(1), rest::bitstring>> = bit_field
    <<pre::bitstring, 0::1, rest::bitstring>>
  end

  @doc """
  Shifts a vector n steps to higher indices. For example, using shift_higher(vector, 1) is
  equivalent in the specs to:
  1. vector[1:] = vector[:size-1]
  2. vector[0] = 0b0

  Internally, this is a left shift, due to the internal big-endian bit representation.
  """
  @spec shift_higher(t, non_neg_integer()) :: t
  def shift_higher(bit_field, steps) do
    <<_::size(steps), remaining::bitstring>> = bit_field
    <<remaining::bitstring, 0::size(steps)>>
  end

  @doc """
  Shifts a vector n steps to the lower indices. For example, using left_shift(vector, 1) is
  equivalent in the specs to:
  1. vector[:size-1] = vector[1:]
  2. vector[size-1] = 0b0

  Internally, this is a left shift, due to the internal big-endian bit representation.
  """
  @spec shift_lower(t, non_neg_integer) :: t
  def shift_lower(bit_field, steps) do
    <<remaining::size(bit_size(bit_field) - steps)-bitstring, _::bitstring>> = bit_field
    <<0::size(steps), remaining::bitstring>>
  end

  @doc """
  Returns the amount of bits set.
  """
  @spec count(t) :: non_neg_integer()
  def count(bit_field), do: for(<<bit::1 <- bit_field>>, do: bit) |> Enum.sum()
end
