alias LambdaEthereumConsensus.SszEx.Decode
alias LambdaEthereumConsensus.SszEx.Encode
alias LambdaEthereumConsensus.SszEx.Merkleization
alias LambdaEthereumConsensus.Store.StateDb
alias Types.BeaconState

# To run these benchmarks, you need a BeaconState stored in the Db beforehand.
# The --mode db flag is also needed.

{:ok, state} = StateDb.get_latest_state()
:mainnet = ChainSpec.get_preset()
{:ok, encoded_state} = Ssz.to_ssz(state)

Benchee.run(
  %{
    "Decode.decode" => fn -> Decode.decode(encoded_state, BeaconState) end,
    "Ssz.from_ssz" => fn -> Ssz.from_ssz(encoded_state, BeaconState) end
  },
  warmup: 2,
  time: 5
)

Benchee.run(
  %{
    "Encode.encode" => fn -> Encode.encode(state, BeaconState) end,
    "Ssz.to_ssz" => fn -> Ssz.to_ssz(state) end
  },
  warmup: 2,
  time: 5
)

Benchee.run(
  %{
    "Merkleization.hash_tree_root!" => fn ->
      Merkleization.hash_tree_root!(state, BeaconState)
    end,
    "Ssz.hash_tree_root" => fn -> Ssz.hash_tree_root(state, BeaconState) end
  },
  warmup: 2,
  time: 30
)
