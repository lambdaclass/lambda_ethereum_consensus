defmodule EpochProcessingTestRunner do
  @moduledoc """
  Runner for Epoch Processing test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/epoch_processing
  """
  alias LambdaEthereumConsensus.StateTransition.EpochProcessing
  alias LambdaEthereumConsensus.Utils.Diff
  alias Types.BeaconState

  use ExUnit.CaseTemplate
  use TestRunner

  # TODO: We need to make sure this 2 are still needed to be here
  @disabled_handlers [
    "participation_record_updates"
  ]

  @deprecated_handlers [
    "historical_roots_update"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "capella", handler: handler}) do
    Enum.member?(@disabled_handlers ++ @deprecated_handlers, handler)
  end

  def skip?(_), do: false

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
