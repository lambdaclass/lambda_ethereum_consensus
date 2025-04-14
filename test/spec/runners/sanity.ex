defmodule SanityTestRunner do
  @moduledoc """
  Runner for Sanity test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/sanity
  """

  use ExUnit.CaseTemplate
  use TestRunner

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.Utils.Diff
  alias Types.BeaconState

  # TODO: We need to make sure this is still needed to be here
  @disabled_cases [
    "historical_accumulator"
  ]

  @handlers [
    "blocks",
    "slots"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "capella", handler: handler, case: testcase})
      when handler in @handlers,
      do: Enum.member?(@disabled_cases, testcase)

  def skip?(%SpecTestCase{fork: "deneb", handler: handler, case: testcase})
      when handler in @handlers,
      do: Enum.member?(@disabled_cases, testcase)

  def skip?(%SpecTestCase{fork: "electra", handler: handler, case: testcase})
      when handler in @handlers,
      do: Enum.member?(@disabled_cases, testcase)

  def skip?(_), do: true

  @impl TestRunner
  def run_test_case(%SpecTestCase{handler: "slots"} = testcase) do
    # TODO process meta.yaml
    case_dir = SpecTestCase.dir(testcase)

    pre = SpecTestUtils.read_ssz_from_file!(case_dir <> "/pre.ssz_snappy", BeaconState)
    post = SpecTestUtils.read_ssz_from_optional_file!(case_dir <> "/post.ssz_snappy", BeaconState)

    slots_to_process =
      YamlElixir.read_from_file!(case_dir <> "/slots.yaml") |> SpecTestUtils.sanitize_yaml()

    assert is_integer(slots_to_process)

    case StateTransition.process_slots(pre, pre.slot + slots_to_process) do
      {:ok, state} ->
        assert Diff.diff(state, post) == :unchanged

      {:error, error} ->
        assert post == nil, "Process slots failed, error: #{error}"
    end
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{handler: "blocks"} = testcase) do
    # TODO process meta.yaml
    Helpers.ProcessBlocks.process_blocks(testcase)
  end
end
