import Bitwise
alias LambdaEthereumConsensus.Utils.BitVector

reverse_number = fn bits ->
  bitsize = bit_size(bits)
  <<num::integer-little-size(bitsize)>> = bits
  <<num::integer-size(bitsize)>>
end

reverse_list = fn bits ->
  bits |> :binary.bin_to_list() |> Enum.reverse() |> :binary.list_to_bin()
end

reverse_comprehension = fn bits ->
  for <<byte <- bits>>, do: <<byte>>, into: <<>>
end

bits = for i <- 1..512, do: <<i>>, into: <<>>

Benchee.run(
  %{
    "number" => fn -> reverse_number.(bits) end,
    "list" => fn -> reverse_list.(bits) end,
    "comprehension" => fn -> reverse_comprehension.(bits) end
  },
  time: 10,
  memory_time: 2
)
