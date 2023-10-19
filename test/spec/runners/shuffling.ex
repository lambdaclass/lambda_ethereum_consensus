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

    %{seed: seed, count: index_count, mapping: indices} =
      YamlElixir.read_from_file!(case_dir <> "/mapping.yaml")
      |> SpecTestUtils.parse_yaml()


    IO.puts(seed)

    handle(testcase.handler, seed, index_count, indices)
  end

  defp handle("core", seed, index_count, indices) do
    for index <- 0..(index_count - 1) do
      result = Misc.compute_shuffled_index(index, index_count, seed)
      case result do
        {:ok, value} ->
          assert Enum.fetch!(indices, value) == Enum.fetch!(indices, index)

        {:error, _} ->
          assert index >= index_count or index_count == 0
      end
    end
  end
end
