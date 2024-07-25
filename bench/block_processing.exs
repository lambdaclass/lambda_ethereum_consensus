alias LambdaEthereumConsensus.ForkChoice
alias LambdaEthereumConsensus.ForkChoice.Handlers
alias LambdaEthereumConsensus.StateTransition.Cache
alias LambdaEthereumConsensus.Store
alias LambdaEthereumConsensus.Store.BlockBySlot
alias LambdaEthereumConsensus.Store.BlockDb
alias LambdaEthereumConsensus.Store.StateDb
alias Types.BeaconState
alias Types.BlockInfo
alias Types.SignedBeaconBlock
alias Types.StateInfo

Logger.configure(level: :warning)
Cache.initialize_cache()

# NOTE: this slot must be at the beginning of an epoch (i.e. a multiple of 32)
slot = 9_591_424

IO.puts("fetching blocks...")
{:ok, %StateInfo{beacon_state: state}} = StateDb.get_state_by_slot(slot)
{:ok, %BlockInfo{signed_block: block}} = BlockDb.get_block_info_by_slot(slot)
{:ok, %BlockInfo{signed_block: new_block} = block_info} = BlockDb.get_block_info_by_slot(slot + 1)

IO.puts("initializing store...")
{:ok, store} = Types.Store.get_forkchoice_store(state, block)
store = Handlers.on_tick(store, store.time + 30)

{:ok, root} = BlockBySlot.get(slot)

IO.puts("about to process block: #{slot + 1}, with root: #{Base.encode16(root)}...")
IO.puts("#{length(attestations)} attestations ; #{length(attester_slashings)} attester slashings")
IO.puts("")

if System.get_env("FLAMA") do
  Flama.run({ForkChoice, :process_block, [block_info, store]})
else
  Benchee.run(
    %{
      "block (full cache)" => fn ->
        ForkChoice.process_block(block_info, store)
      end
    },
    time: 30
  )

  Benchee.run(
    %{
      "block (empty cache)" => fn _ ->
        ForkChoice.process_block(block_info, store)
      end
    },
    time: 30,
    before_each: fn _ -> Cache.clear_cache() end
  )
end
