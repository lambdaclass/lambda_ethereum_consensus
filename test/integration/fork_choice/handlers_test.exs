defmodule Integration.ForkChoice.HandlersTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.ForkChoice.Helpers
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.StateTransition.Operations
  alias LambdaEthereumConsensus.Store.BlockStore
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.StateStore
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  setup_all do
    start_supervised!(Db)
    :ok
  end

  # @tag :skip
  test "on_block w/data from DB" do
    # NOTE: this test requires a DB with a state, and blocks for the state's slot and the next slot.
    # WARN: sometimes fails with "OffsetOutOfBounds" errors. Re-run the test in those cases.
    {:ok, state} = StateStore.get_latest_state()

    {:ok, v} = Ssz.to_ssz(state)
    {:ok, c} = :snappyer.compress(v)
    File.write!("bench/latest_state.ssz", c)

    {:ok, signed_block} = BlockStore.get_block_by_slot(state.slot)
    {:ok, new_signed_block} = BlockStore.get_block_by_slot(state.slot + 1)

    # {:ok, s} = File.read!("bench/state.ssz") |> :snappyer.decompress()
    # {:ok, att_state} = Ssz.from_ssz(s, BeaconState)

    Cache.initialize_tables()

    start_time = DateTime.utc_now()
    IO.puts("[#{start_time}] start")

    # attestations = new_signed_block.message.body.attestations
    # assert {:ok, _} = Operations.process_attestation_batch(att_state, attestations)

    assert {:ok, store} = Helpers.get_forkchoice_store(state, signed_block.message)
    new_store = Handlers.on_tick(store, :os.system_time(:second))
    assert {:ok, _} = Handlers.on_block(new_store, new_signed_block)

    end_time = DateTime.utc_now()
    IO.puts("[#{end_time}] end")
    diff = DateTime.diff(end_time, start_time, :millisecond)
    avg = diff / length(new_signed_block.message.body.attestations)
    IO.puts("Elapsed: #{diff}")
    IO.puts("Avg. per attestation: #{avg}")
  end
end
