defmodule FinalityTestRunner do
  @moduledoc """
  Runner for finality test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/finality
  """

  use ExUnit.CaseTemplate
  use TestRunner

  @disabled_cases [
    # "finality_no_updates_at_genesis",
    # "finality_rule_1",
    # "finality_rule_2",
    # "finality_rule_3",
    # "finality_rule_4"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "capella", case: testcase}) do
    Enum.member?(@disabled_cases, testcase)
  end

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "deneb", case: testcase}) do
    Enum.member?(@disabled_cases, testcase)
  end

  @impl TestRunner
  def skip?(_), do: true

  @impl TestRunner
  def run_test_case(testcase) do
    Helpers.ProcessBlocks.process_blocks(testcase)
  end
end
