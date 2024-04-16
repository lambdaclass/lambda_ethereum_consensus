alias LambdaEthereumConsensus.ForkChoice
alias LambdaEthereumConsensus.ForkChoice.Handlers
alias LambdaEthereumConsensus.StateTransition.Cache
alias LambdaEthereumConsensus.Store
alias LambdaEthereumConsensus.Store.BlockDb
alias LambdaEthereumConsensus.Store.StateDb
alias Types.BeaconState
alias Types.SignedBeaconBlock

Logger.configure(level: :warning)

{:ok, _} = Store.Db.start_link([])
{:ok, _} = Store.Blocks.start_link([])
{:ok, _} = Store.BlockStates.start_link([])
Cache.initialize_cache()

# NOTE: this slot must be at the beginning of an epoch (i.e. a multiple of 32)
slot = 4_213_280

IO.puts("fetching blocks...")
{:ok, %BeaconState{} = state} = StateDb.get_state_by_slot(slot)
{:ok, %SignedBeaconBlock{} = block} = BlockDb.get_block_by_slot(slot)
{:ok, %SignedBeaconBlock{} = new_block} = BlockDb.get_block_by_slot(slot + 1)

IO.puts("initializing store...")
{:ok, store} = Types.Store.get_forkchoice_store(state, block)
store = Handlers.on_tick(store, store.time + 30)

attestations = new_block.message.body.attestations
attester_slashings = new_block.message.body.attester_slashings

{:ok, root} = BlockDb.get_block_root_by_slot(slot)

IO.puts("about to process block: #{slot + 1}, with root: #{Base.encode16(root)}...")
IO.puts("#{length(attestations)} attestations ; #{length(attester_slashings)} attester slashings")
IO.puts("")

on_block = fn ->
  # process block attestations
  {:ok, new_store} = Handlers.on_block(store, new_block)

  {:ok, new_store} =
    attestations
    |> ForkChoice.apply_handler(new_store, &Handlers.on_attestation(&1, &2, true))

  # process block attester slashings
  {:ok, _} =
    attester_slashings
    |> ForkChoice.apply_handler(new_store, &Handlers.on_attester_slashing/2)
end

Benchee.run(
  %{
    "block (full cache)" => fn -> on_block.() end
  },
  time: 30
)

Benchee.run(
  %{
    "block (empty cache)" => fn _ -> on_block.() end
  },
  time: 30,
  before_each: fn _ -> Cache.clear_cache() end
)
