defmodule LambdaEthereumConsensus.Utils.BitVector do
  def new(number, s) when is_integer(number), do: <<number::size(s)>>

  def set?(bit_vector, index) do
    skip = bit_size(bit_vector) - index - 1
    match?(<<_::size(skip), 1::size(1), _::bitstring>>, bit_vector)
  end

  def all?(bit_vector, first..last) do
    skip = bit_size(bit_vector) - last
    range_size = last - first
    target = 2 ** range_size - 1
    match?(<<_::size(skip), ^target::size(range_size), _::bitstring>>, bit_vector)
  end
end
