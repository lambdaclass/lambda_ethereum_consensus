defmodule LambdaEthereumConsensus.StateTransition.AtomicBitVector do
  @moduledoc """
  Efficient bit vector backed by `:atomics` for O(1) membership testing.

  Used to replace MapSet for large validator index sets (~1M validators).
  Each atomic word holds 64 bits, so a 1M-validator set uses ~125KB
  compared to megabytes for a MapSet of integer keys.
  """

  @bits_per_word 64

  @type t :: %__MODULE__{ref: :atomics.atomics_ref(), size: non_neg_integer()}
  defstruct [:ref, :size]

  @doc """
  Create a new bit vector that can hold `size` bits, all initially unset.
  """
  @spec new(non_neg_integer()) :: t()
  def new(size) do
    words = div(size + @bits_per_word - 1, @bits_per_word)
    ref = :atomics.new(max(words, 1), signed: false)
    %__MODULE__{ref: ref, size: size}
  end

  @doc """
  Set the bit at `index` (0-based).
  """
  @spec set(t(), non_neg_integer()) :: :ok
  def set(%__MODULE__{ref: ref}, index) do
    word_index = div(index, @bits_per_word) + 1
    bit_position = rem(index, @bits_per_word)
    current = :atomics.get(ref, word_index)
    :atomics.put(ref, word_index, Bitwise.bor(current, Bitwise.bsl(1, bit_position)))
    :ok
  end

  @doc """
  Test whether the bit at `index` (0-based) is set.
  """
  @spec member?(t(), non_neg_integer()) :: boolean()
  def member?(%__MODULE__{ref: ref}, index) do
    word_index = div(index, @bits_per_word) + 1
    bit_position = rem(index, @bits_per_word)
    current = :atomics.get(ref, word_index)
    Bitwise.band(current, Bitwise.bsl(1, bit_position)) != 0
  end
end
