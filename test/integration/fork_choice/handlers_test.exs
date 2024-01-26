defmodule Integration.ForkChoice.HandlersTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStore
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.StateStore

  setup_all do
    start_supervised!(Db)
    start_supervised!(Blocks)
    Cache.initialize_cache()
    :ok
  end

  @tag :skip
  test "on_block w/data from DB" do
    # NOTE: this test requires a DB with a state, and blocks for the state's slot and the next slot.
    # WARN: sometimes fails with "OffsetOutOfBounds" errors. Re-run the test in those cases.
    {:ok, state} = StateStore.get_latest_state()

    {:ok, signed_block} = BlockStore.get_block_by_slot(state.slot)
    {:ok, new_signed_block} = BlockStore.get_block_by_slot(state.slot + 1)

    assert {:ok, store} = Types.Store.get_forkchoice_store(state, signed_block)
    new_store = Handlers.on_tick(store, :os.system_time(:second))

    assert {:ok, _} = Handlers.on_block(new_store, new_signed_block)
  end

  @tag :skip
  test "multiple on_block w/data from DB" do
    # NOTE: this test requires a DB with the initial state and all blocks in the given range.
    #  It assumes missing blocks to be empty slots. It also needs `slot` to be at the start of an epoch.
    start_slot = 4_191_040
    count = 100
    end_slot = start_slot + count
    {:ok, state} = StateStore.get_state_by_slot(start_slot)
    {:ok, signed_block} = BlockStore.get_block_by_slot(state.slot)

    blocks =
      (start_slot + 1)..end_slot
      # NOTE: we have to consider empty slots
      |> Enum.flat_map(fn slot ->
        case BlockStore.get_block_by_slot(slot) do
          {:ok, block} -> [block]
          :not_found -> []
        end
      end)

    assert {:ok, store} = Types.Store.get_forkchoice_store(state, signed_block, true)
    new_store = Handlers.on_tick(store, :os.system_time(:second))

    IO.puts("Running slots from #{start_slot} to #{end_slot}")

    start_time = System.monotonic_time(:millisecond)

    Enum.reduce(blocks, new_store, fn block, store ->
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, new_store} = Handlers.on_block(store, block)

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
  end
end
