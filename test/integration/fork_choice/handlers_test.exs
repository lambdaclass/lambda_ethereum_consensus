defmodule Integration.ForkChoice.HandlersTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.ForkChoice.Helpers
  alias LambdaEthereumConsensus.Store.BlockStore
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.StateStore

  setup_all do
    start_supervised!(Db)
    :ok
  end

  @tag :skip
  test "on_block w/data from DB" do
    # NOTE: this test requires a DB with a state, and blocks for the state's slot and the next slot.
    # WARN: sometimes fails with "OffsetOutOfBounds" errors. Re-run the test in those cases.
    {:ok, state} = StateStore.get_latest_state()

    {:ok, signed_block} = BlockStore.get_block_by_slot(state.slot)
    {:ok, new_signed_block} = BlockStore.get_block_by_slot(state.slot + 1)

    assert {:ok, store} = Helpers.get_forkchoice_store(state, signed_block.message, false)
    new_store = Handlers.on_tick(store, :os.system_time(:second))

    assert {:ok, _} = Handlers.on_block(new_store, new_signed_block)
  end
end
