defmodule Integration.ForkChoice.HandlersTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.StateDb
  alias Types.BlockInfo

  setup_all do
    start_supervised!(Db)
    start_supervised!(Blocks)
    start_supervised!(BlockStates)
    Cache.initialize_cache()
    :ok
  end

  # TODO: refactor to use randomized fixtures
  @tag :skip
  test "on_block w/data from DB" do
    # NOTE: this test requires a DB with a state, and blocks for the state's slot and the next slot.
    # WARN: sometimes fails with "OffsetOutOfBounds" errors. Re-run the test in those cases.
    {:ok, state} = StateDb.get_latest_state()

    {:ok, %BlockInfo{signed_block: signed_block}} = BlockDb.get_block_info_by_slot(state.slot)

    {:ok, %BlockInfo{signed_block: new_signed_block}} =
      BlockDb.get_block_info_by_slot(state.slot + 1)

    assert {:ok, store} = Types.Store.get_forkchoice_store(state, signed_block)
    new_store = Handlers.on_tick(store, :os.system_time(:second))

    assert {:ok, _} = Handlers.on_block(new_store, new_signed_block)
  end
end
