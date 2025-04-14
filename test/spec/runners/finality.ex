defmodule FinalityTestRunner do
  @moduledoc """
  Runner for finality test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/finality
  """

  use ExUnit.CaseTemplate
  use TestRunner

  @impl TestRunner
  def skip?(_), do: false

  @impl TestRunner
  def run_test_case(testcase) do
    Helpers.ProcessBlocks.process_blocks(testcase)
  end
end
