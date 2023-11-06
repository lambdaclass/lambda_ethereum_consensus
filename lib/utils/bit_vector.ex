defmodule LambdaEthereumConsensus.Utils.BitVector do
  def new(number, s) when is_integer(number), do: <<number::size(s)>>
end
