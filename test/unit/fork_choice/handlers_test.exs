defmodule Unit.ForkChoice.HandlersTest do
  use ExUnit.Case

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.Utils.Diff
  alias SszTypes.Store

  doctest Handlers

  @empty_store %Store{
    genesis_time: 0,
    proposer_boost_root: <<0::256>>
  }

  describe "on_tick" do
    test "updates the Store's time to current time" do
      start_time = 0
      end_time = start_time + 1

      start_store = %Store{@empty_store | time: start_time}
      end_store = %Store{start_store | time: end_time}

      assert Diff.diff(Handlers.on_tick(start_store, end_time), end_store) == :unchanged
    end

    test "doesn't reset proposer_boost_root when slot didn't change" do
      start_time = 0
      end_time = start_time + 1

      start_store = %Store{@empty_store | time: start_time, proposer_boost_root: <<1::256>>}
      end_store = %Store{start_store | time: end_time}

      assert Diff.diff(Handlers.on_tick(start_store, end_time), end_store) == :unchanged
    end

    test "resets proposer_boost_root when slot changed" do
      start_time = 1
      end_time = start_time + ChainSpec.get("SECONDS_PER_SLOT")

      start_store = %Store{@empty_store | time: start_time, proposer_boost_root: <<1::256>>}
      end_store = %Store{start_store | time: end_time, proposer_boost_root: <<0::256>>}

      assert Diff.diff(Handlers.on_tick(start_store, end_time), end_store) == :unchanged
    end

    test "upgrades unrealized checkpoints" do
      start_time = 0
      end_time = start_time + ChainSpec.get("SECONDS_PER_SLOT") * ChainSpec.get("SLOTS_PER_EPOCH")

      justified = %SszTypes.Checkpoint{epoch: 0, root: <<0::256>>}
      finalized = %SszTypes.Checkpoint{epoch: 0, root: <<1::256>>}
      unjustified = %SszTypes.Checkpoint{epoch: 1, root: <<2::256>>}
      unfinalized = %SszTypes.Checkpoint{epoch: 1, root: <<3::256>>}

      start_store = %Store{
        @empty_store
        | time: start_time,
          justified_checkpoint: justified,
          finalized_checkpoint: finalized,
          unrealized_justified_checkpoint: unjustified,
          unrealized_finalized_checkpoint: unfinalized
      }

      end_store = %Store{
        start_store
        | time: end_time,
          justified_checkpoint: unjustified,
          finalized_checkpoint: unfinalized
      }

      assert Diff.diff(Handlers.on_tick(start_store, end_time), end_store) == :unchanged
    end
  end
end
