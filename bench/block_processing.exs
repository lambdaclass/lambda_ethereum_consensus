alias LambdaEthereumConsensus.ForkChoice
alias LambdaEthereumConsensus.ForkChoice.Handlers
alias LambdaEthereumConsensus.StateTransition.Cache
alias LambdaEthereumConsensus.Store.BlockDb
alias LambdaEthereumConsensus.Store.StateDb
alias Types.BlockInfo
alias Types.StateInfo
alias Utils.Date

Logger.configure(level: :warning)
Cache.initialize_cache()

# NOTE: this slot must be at the beginning of an epoch (i.e. a multiple of 32)
slot = 9_649_056

IO.puts("Fetching state and blocks...")
{:ok, %StateInfo{beacon_state: state}} = StateDb.get_state_by_slot(slot)
{:ok, %BlockInfo{signed_block: block}} = BlockDb.get_block_info_by_slot(slot)
{:ok, %BlockInfo{} = block_info} = BlockDb.get_block_info_by_slot(slot + 1)
{:ok, %BlockInfo{} = block_info_2} = BlockDb.get_block_info_by_slot(slot + 2)

IO.puts("Initializing store...")
{:ok, store} = Types.Store.get_forkchoice_store(state, block)
store = Handlers.on_tick(store, store.time + 30)

IO.puts("Processing the block 1...")

{:ok, new_store} = ForkChoice.process_block(block_info, store)
IO.puts("Processing the block 2...")

if System.get_env("FLAMA") do
  filename = "flamegraphs/stacks.#{Date.now_str()}.out"
  Flama.run({ForkChoice, :process_block, [block_info_2, new_store]}, output_file: filename)
  IO.puts("Flamegraph saved to #{filename}")
else
  Benchee.run(
    %{
      "block (full cache)" => fn ->
        ForkChoice.process_block(block_info_2, new_store)
      end
    },
    time: 30
  )

  Benchee.run(
    %{
      "block (empty cache)" => fn _ ->
        ForkChoice.process_block(block_info_2, new_store)
      end
    },
    time: 30,
    before_each: fn _ -> Cache.clear_cache() end
  )
end
