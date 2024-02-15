defmodule ShufflingTestRunner do
  @moduledoc """
  Runner for Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/shuffling
  """

  use ExUnit.CaseTemplate
  use TestRunner

  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Shuffling

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

    %{seed: seed, count: index_count, mapping: indices} =
      YamlElixir.read_from_file!(case_dir <> "/mapping.yaml")
      |> SpecTestUtils.sanitize_yaml()

    handle(testcase.handler, seed, index_count, indices)
  end

  defp handle("core", seed, index_count, indices) do
    # Testing permute-index by running it for every index in 0..(index_count - 1) and check against expected mapping[i]
    for index <- 0..(index_count - 1) do
      result = Misc.compute_shuffled_index(index, index_count, seed)

      if index >= index_count or index_count == 0 do
        assert result == {:error, "invalid index_count"}
      else
        assert result == {:ok, Enum.fetch!(indices, index)}
      end
    end

    shuffled_list =
      Shuffling.shuffle_list(0..(index_count - 1)//1 |> Aja.Vector.new(), seed)
      |> Aja.Enum.to_list()

    assert shuffled_list == indices
  end
end
