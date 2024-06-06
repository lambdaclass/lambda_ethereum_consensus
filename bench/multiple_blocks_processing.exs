alias LambdaEthereumConsensus.ForkChoice
alias LambdaEthereumConsensus.ForkChoice.Handlers
alias LambdaEthereumConsensus.StateTransition.Cache
alias LambdaEthereumConsensus.Store
alias LambdaEthereumConsensus.Store.BlockDb
alias LambdaEthereumConsensus.Store.StateDb
alias Types.BeaconState
alias Types.BlockInfo
alias Types.SignedBeaconBlock

Logger.configure(level: :warning)

{:ok, _} = Store.Db.start_link([])
{:ok, _} = Store.Blocks.start_link([])
{:ok, _} = Store.BlockStates.start_link([])
Cache.initialize_cache()

# NOTE: this slot must be at the beginning of an epoch (i.e. a multiple of 32)
start_slot = 4_213_280
count = 10
end_slot = start_slot + count

IO.puts("fetching blocks...")
{:ok, %BeaconState{} = state} = StateDb.get_state_by_slot(start_slot)
{:ok, %BlockInfo{signed_block: signed_block}} = BlockDb.get_block_info_by_slot(state.slot)

blocks =
  (start_slot + 1)..end_slot
  # NOTE: we have to consider empty slots
  |> Enum.flat_map(fn slot ->
    case BlockDb.get_block_info_by_slot(slot) do
      {:ok, %BlockInfo{signed_block: block}} -> [block]
      :not_found -> []
    end
  end)

IO.puts("initializing store...")
{:ok, store} = Types.Store.get_forkchoice_store(state, signed_block)
store = Handlers.on_tick(store, :os.system_time(:second))

IO.puts("Running slots from #{start_slot} to #{end_slot}")

start_time = System.monotonic_time(:millisecond)

Enum.reduce(blocks, store, fn block, store ->
  start_time = System.monotonic_time(:millisecond)
  {:ok, new_store} = Handlers.on_block(store, block)

  # process block attestations
  {:ok, new_store} =
    signed_block.message.body.attestations
    |> ForkChoice.apply_handler(new_store, &Handlers.on_attestation(&1, &2, true))

  # process block attester slashings
  {:ok, new_store} =
    signed_block.message.body.attester_slashings
    |> ForkChoice.apply_handler(new_store, &Handlers.on_attester_slashing/2)

  end_time = System.monotonic_time(:millisecond)
  IO.puts("Slot #{block.message.slot} took #{end_time - start_time} ms")
  new_store
end)

end_time = System.monotonic_time(:millisecond)
IO.puts("Total: took #{end_time - start_time} ms")
