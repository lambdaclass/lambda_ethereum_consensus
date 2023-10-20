defmodule EpochProcessingTestRunner do
  alias LambdaEthereumConsensus.StateTransition.EpochProcessing

  use ExUnit.CaseTemplate
  use TestRunner

  @moduledoc """
  Runner for Epoch Processing test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/epoch_processing
  """

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    "justification_and_finalization",
    # "inactivity_updates",
    "rewards_and_penalties",
    "registry_updates",
    "slashings",
    # "effective_balance_updates",
    # "eth1_data_reset",
    # "slashings_reset",
    # "randao_mixes_reset",
    "historical_summaries_update",
    "participation_record_updates",
    # "participation_flag_updates",
    "sync_committee_updates"
  ]

  @deprecated_handlers [
    "historical_roots_update"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: fork, handler: handler}) do
    fork != "capella" or Enum.member?(@disabled_handlers ++ @deprecated_handlers, handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    pre =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/pre.ssz_snappy",
        SszTypes.BeaconState
      )

    post =
      SpecTestUtils.read_ssz_from_optional_file!(
        case_dir <> "/post.ssz_snappy",
        SszTypes.BeaconState
      )

    handle_case(testcase.handler, pre, post)
  end

  defp handle_case("effective_balance_updates", pre, post) do
    result = EpochProcessing.process_effective_balance_updates(pre)
    assert result == {:ok, post}
  end

  defp handle_case("eth1_data_reset", pre, post) do
    result = EpochProcessing.process_eth1_data_reset(pre)
    assert result == {:ok, post}
  end

  defp handle_case("inactivity_updates", pre, post) do
    result = EpochProcessing.process_inactivity_updates(pre)
    assert result == {:ok, post}
  end

  defp handle_case("slashings_reset", pre, post) do
    result = EpochProcessing.process_slashings_reset(pre)
    assert result == {:ok, post}
  end

  defp handle_case("randao_mixes_reset", pre, post) do
    result = EpochProcessing.process_randao_mixes_reset(pre)
    assert result == {:ok, post}
  end

  defp handle_case("participation_flag_updates", pre, post) do
    result = EpochProcessing.process_participation_flag_updates(pre)
    assert result == {:ok, post}
  end
end
