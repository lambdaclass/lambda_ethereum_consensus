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
