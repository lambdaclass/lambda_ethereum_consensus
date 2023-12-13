defmodule SyncTestRunner do
  @moduledoc """
  Runner for Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/sync
  """

  use ExUnit.CaseTemplate
  use TestRunner

  @disabled_cases [
    # TODO: we have to support https://github.com/ethereum/consensus-specs/blob/dev/tests/formats/fork_choice/README.md#on_payload_info-execution-step
    "from_syncing_to_invalid"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_cases, testcase.case)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    ForkChoiceTestRunner.run_test_case(testcase)
  end
end
