defmodule RandomTestRunner do
  @moduledoc """
  Runner for random test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/random
  """

  use ExUnit.CaseTemplate
  use TestRunner

  @impl TestRunner
  def run_test_case(testcase) do
    Helpers.ProcessBlocks.process_blocks(testcase)
  end
end
