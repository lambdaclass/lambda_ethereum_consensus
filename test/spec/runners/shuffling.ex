defmodule ShufflingTestRunner do

  alias LambdaEthereumConsensus.StateTransition.Misc
  use ExUnit.CaseTemplate
  use TestRunner

  @moduledoc """
  Runner for Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/shuffling
  """

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    # "core"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    %{seed: seed, count: count, mapping: mapping} =
      YamlElixir.read_from_file!(case_dir <> "/mapping.yaml")
      |> SpecTestUtils.parse_yaml()

    for i <- 0..count do
      {:ok, value} = Misc.compute_shuffled_index(i, count, seed)
      assert value == Enum.fetch!(mapping, i)
    end
  end
end
