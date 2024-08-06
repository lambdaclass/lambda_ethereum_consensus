defmodule Unit.StateTransition.MiscTest do
  alias Fixtures.Block
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Utils.Diff

  use ExUnit.Case

  setup_all do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MinimalConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  test "Calculating all committees for a single epoch should be the same by any method" do
    state = Block.beacon_state_from_file().beacon_state
    epoch = Accessors.get_current_epoch(state)
    committees = Misc.compute_all_committees(state, epoch)

    assert_all_committees_equal(committees, calculate_all_individually(state, epoch))
  end

  defp calculate_all_individually(state, epoch) do
    committee_count_per_slot = Accessors.get_committee_count_per_slot(state, epoch)
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")

    for slot <- state.slot..(state.slot + slots_per_epoch - 1),
        index <- 0..(committee_count_per_slot - 1) do
      Accessors.get_beacon_committee(state, slot, index)
    end
  end

  defp assert_all_committees_equal(all_committees, all_committees_individual) do
    adapted_committees = Enum.map(all_committees, &{:ok, &1})
    assert Diff.diff(adapted_committees, all_committees_individual) == :unchanged
  end
end
