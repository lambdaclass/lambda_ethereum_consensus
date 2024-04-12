alias LambdaEthereumConsensus.SszEx
alias LambdaEthereumConsensus.Store.StateDb
alias Types.BeaconState

# To run this benchmarks, checkpoint-sync is needed.

{:ok, state} = StateDb.get_latest_state()
:mainnet = ChainSpec.get_preset()
{:ok, encoded_state} = Ssz.to_ssz(state)

Benchee.run(
  %{
    "SszEx.decode" => fn -> SszEx.decode(encoded_state, BeaconState) end,
    "Ssz.from_ssz" => fn -> Ssz.from_ssz(encoded_state, BeaconState) end
  },
  warmup: 2,
  time: 5
)

Benchee.run(
  %{
    "SszEx.encode" => fn -> SszEx.encode(state, BeaconState) end,
    "Ssz.to_ssz" => fn -> Ssz.to_ssz(state) end
  },
  warmup: 2,
  time: 5
)

Benchee.run(
  %{
    "SszEx.hash_tree_root!" => fn -> SszEx.hash_tree_root!(state, BeaconState) end,
    "Ssz.hash_tree_root" => fn -> Ssz.hash_tree_root(state, BeaconState) end
  },
  warmup: 2,
  time: 30
)
