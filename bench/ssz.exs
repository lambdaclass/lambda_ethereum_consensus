alias LambdaEthereumConsensus.SszEx
alias Types.Checkpoint

checkpoint = %Checkpoint{
  epoch: 12_345,
  root: Base.decode16!("0100000000000000000000000000000000000000000000000000000000000001")
}

Benchee.run(
  %{
    "SszEx.encode" => fn {v, schema} -> SszEx.encode(v, schema) end,
    "Ssz.to_ssz" => fn {v, _schema} -> Ssz.to_ssz(v) end
  },
  inputs: %{
    "Checkpoint" => {checkpoint, Checkpoint}
  },
  warmup: 2,
  time: 5
)

serialized =
  Base.decode16!(
    "39300000000000000100000000000000000000000000000000000000000000000000000000000001"
  )

Benchee.run(
  %{
    "SszEx.decode" => fn {b, schema} -> SszEx.decode(b, schema) end,
    "Ssz.from_ssz" => fn {b, schema} -> Ssz.from_ssz(b, schema) end
  },
  inputs: %{
    "Checkpoint" => {serialized, Checkpoint}
  },
  warmup: 2,
  time: 5
)

## Benchmark Merkleization

list = Stream.cycle([65_535]) |> Enum.take(316)
schema = {:list, {:int, 16}, 1024}
packed_chunks = SszEx.pack(list, schema)
limit = SszEx.chunk_count(schema)

Benchee.run(
  %{
    "SszEx.merkleize_chunks" => fn {chunks, leaf_count} ->
      SszEx.merkleize_chunks(chunks, leaf_count)
    end,
    "SszEx.merkleize_chunks_with_virtual_padding" => fn {chunks, leaf_count} ->
      SszEx.merkleize_chunks_with_virtual_padding(chunks, leaf_count)
    end
  },
  inputs: %{
    "args" => {packed_chunks, limit}
  },
  warmup: 2,
  time: 5
)
