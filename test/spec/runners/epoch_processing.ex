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
    "inactivity_updates",
    "rewards_and_penalties",
    "registry_updates",
    "slashings",
    # "eth1_data_reset",
    "effective_balance_updates",
    "slashings_reset",
    "randao_mixes_reset",
    "historical_summaries_update",
    "participation_record_updates",
    "participation_flag_updates",
    "sync_committee_updates"
  ]

  @deprecated_handlers [
    "historical_roots_update"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers ++ @deprecated_handlers, testcase.handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    config = SpecTestUtils.get_config(testcase.config)

    _pre =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/pre.ssz_snappy",
        SszTypes.BeaconState,
        config
      )

    {:ok, _post} =
      SpecTestUtils.read_ssz_from_file(
        case_dir <> "/post.ssz_snappy",
        SszTypes.BeaconState,
        config
      )

    # handle_case(testcase.handler, pre, post)
  end

  def handle_case("eth1_data_reset", pre, post) do
    result = EpochProcessing.process_eth1_data_reset(pre)

    case post do
      nil -> elem(result, 0) == :error
      post -> assert {:ok, post} == result
    end
  end
end
