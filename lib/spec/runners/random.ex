defmodule RandomTestRunner do
  @moduledoc """
  Runner for random test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/random
  """

  use ExUnit.CaseTemplate
  use TestRunner

  @disabled_cases [
    # "randomized_0",
    # "randomized_1",
    # "randomized_2",
    # "randomized_3",
    # "randomized_4",
    # "randomized_5",
    # "randomized_6",
    # "randomized_7",
    # "randomized_8",
    # "randomized_9",
    # "randomized_10",
    # "randomized_11",
    # "randomized_12",
    # "randomized_13",
    # "randomized_14",
    # "randomized_15"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: "capella", case: testcase}) do
    Enum.member?(@disabled_cases, testcase)
  end

  @impl TestRunner
  def run_test_case(testcase) do
    Helpers.ProcessBlocks.process_blocks(testcase)
  end
end
