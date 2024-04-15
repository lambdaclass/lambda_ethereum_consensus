alias LambdaEthereumConsensus.SszEx
alias LambdaEthereumConsensus.SszEx.Merkleization
alias LambdaEthereumConsensus.Store.StateDb
alias Types.BeaconState

# To run these benchmarks, you need a BeaconState stored in the Db beforehand.
# The --mode db flag is also needed.

{:ok, state} = StateDb.get_latest_state()
:mainnet = ChainSpec.get_preset()

Benchee.run(
  %{
    "SszEx.hash_tree_root!" => fn {v, schema} -> SszEx.hash_tree_root!(v, schema) end,
    "Ssz.hash_tree_root" => fn {v, schema} -> Ssz.hash_tree_root(v, schema) end
  },
  warmup: 2,
  time: 30,
  inputs: %{
    "BeaconState" => {state, BeaconState}
  }
)

list = Stream.cycle([65_535]) |> Enum.take(316)
schema = {:list, {:int, 16}, 1024}
packed_chunks = Merkleization.pack(list, schema)
limit = Merkleization.chunk_count(schema)

Benchee.run(
  %{
    "Merkleization.merkleize_chunks" => fn {chunks, leaf_count} ->
      Merkleization.merkleize_chunks(chunks, leaf_count)
    end,
    "Merkleization.merkleize_chunks_with_virtual_padding" => fn {chunks, leaf_count} ->
      Merkleization.merkleize_chunks_with_virtual_padding(chunks, leaf_count)
    end
  },
  inputs: %{
    "packed_list" => {packed_chunks, limit}
  },
  warmup: 2,
  time: 5
)
