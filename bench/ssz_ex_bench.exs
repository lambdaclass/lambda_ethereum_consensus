alias LambdaEthereumConsensus.SszEx
alias Types.BeaconState

{:ok, encoded_state} = File.read!("./bench/beacon_state.ssz.snappy") |> Snappy.decompress()

:mainnet = ChainSpec.get_preset()

{:ok, state} = Ssz.from_ssz(encoded_state, BeaconState)

# Benchee.run(
#   %{
#     "SszEx.decode" => fn -> SszEx.decode(encoded_state, BeaconState) end,
#     "Ssz.from_ssz" => fn -> Ssz.from_ssz(encoded_state, BeaconState) end
#   },
#   after_each: fn result ->
#     {:ok, _decoded} = result
#   end,
#   warmup: 2,
#   time: 5
# )

# Benchee.run(
#   %{
#     "SszEx.encode" => fn -> SszEx.encode(state, BeaconState) end,
#     "Ssz.to_ssz" => fn -> Ssz.to_ssz(state) end
#   },
#   after_each: fn result ->
#     {:ok, _encoded} = result
#   end,
#   warmup: 2,
#   time: 5
# )

Benchee.run(
  %{
    "SszEx.hash_tree_root!" => fn -> SszEx.hash_tree_root!(state, BeaconState) end,
    "Ssz.hash_tree_root" => fn -> Ssz.hash_tree_root(state, BeaconState) end
  },
  after_each: fn result ->
    {:ok, encoded} = result
    dbg(encoded |> Base.encode16())
  end,
  warmup: 2,
  time: 5
)
