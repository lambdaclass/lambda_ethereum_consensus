defmodule EpochProcessingTestRunner do
  @moduledoc """
  Runner for Epoch Processing test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/epoch_processing
  """
  alias LambdaEthereumConsensus.StateTransition.EpochProcessing
  alias LambdaEthereumConsensus.Utils.Diff
  alias Types.BeaconState

  use HardForkAliasInjection

  use ExUnit.CaseTemplate
  use TestRunner

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    # "justification_and_finalization",
    # "inactivity_updates",
    # "rewards_and_penalties",
    # "registry_updates",
    # "slashings",
    # "effective_balance_updates",
    # "eth1_data_reset",
    # "slashings_reset",
    # "randao_mixes_reset",
    # "historical_summaries_update",
    "participation_record_updates"
    # "participation_flag_updates",
    # "sync_committee_updates"
  ]

  @deprecated_handlers [
    "historical_roots_update"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "capella", handler: handler}) do
    Enum.member?(@disabled_handlers ++ @deprecated_handlers, handler)
  end

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "deneb"}), do: false

  @impl TestRunner
  def skip?(_), do: true

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    pre = SpecTestUtils.read_ssz_from_file!(case_dir <> "/pre.ssz_snappy", BeaconState)
    post = SpecTestUtils.read_ssz_from_optional_file!(case_dir <> "/post.ssz_snappy", BeaconState)

    handle_case(testcase.handler, pre, post)
  end

  defp handle_case(name, pre, post) do
    fun = "process_#{name}" |> String.to_existing_atom()
    result = apply(EpochProcessing, fun, [pre])

    case post do
      nil ->
        assert {:error, _error_msg} = result

      post ->
        assert {:ok, state} = result
        assert Diff.diff(state, post) == :unchanged
    end
  end
end
