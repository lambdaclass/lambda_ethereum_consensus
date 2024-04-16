alias LambdaEthereumConsensus.SszEx
alias LambdaEthereumConsensus.Store.StateDb
alias Types.BeaconState
alias Types.Checkpoint

# To run these benchmarks, you need a BeaconState stored in the Db beforehand.
# The --mode db flag is also needed.

{:ok, state} = StateDb.get_latest_state()
:mainnet = ChainSpec.get_preset()
{:ok, encoded_state} = Ssz.to_ssz(state)

checkpoint = %Checkpoint{
  epoch: 12_345,
  root: Base.decode16!("0100000000000000000000000000000000000000000000000000000000000001")
}

{:ok, encoded_checkpoint} = Ssz.to_ssz(checkpoint)

Benchee.run(
  %{
    "SszEx.decode" => fn {v, schema} -> SszEx.decode(v, schema) end,
    "Ssz.from_ssz" => fn {v, schema} -> Ssz.from_ssz(v, schema) end
  },
  warmup: 2,
  time: 5,
  inputs: %{
    "BeaconState" => {encoded_state, BeaconState},
    "Checkpoint" => {encoded_checkpoint, Checkpoint}
  }
)

Benchee.run(
  %{
    "SszEx.encode" => fn v -> SszEx.encode(v) end,
    "Ssz.to_ssz" => fn v -> Ssz.to_ssz(v) end
  },
  warmup: 2,
  time: 5,
  inputs: %{
    "BeaconState" => state,
    "Checkpoint" => checkpoint
  }
)
