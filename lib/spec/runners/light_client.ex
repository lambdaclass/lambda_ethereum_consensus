defmodule LightClientTestRunner do
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Predicates
  use ExUnit.CaseTemplate
  use TestRunner

  @moduledoc """
  Runner for LightClient test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/light_client
  """

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    # "single_merkle_proof",
    "sync",
    "update_ranking"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    handle(testcase.handler, testcase)
  end

  defp handle("single_merkle_proof", testcase) do
    case_dir = SpecTestCase.dir(testcase)

    object_root =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/object.ssz_snappy",
        String.to_existing_atom("Elixir.Types." <> testcase.suite)
      )
      |> Ssz.hash_tree_root!()

    %{leaf: leaf, leaf_index: leaf_index, branch: branch} =
      YamlElixir.read_from_file!(case_dir <> "/proof.yaml")
      |> SpecTestUtils.sanitize_yaml()

    res =
      Predicates.is_valid_merkle_branch?(
        leaf,
        branch,
        Constants.deposit_contract_tree_depth() + 1,
        leaf_index,
        object_root
      )

    IO.inspect(branch, label: "branch")
    IO.inspect(Misc.get_merkle_proof_by_branch([leaf] ++ branch), label: "res")
    assert true == res
  end
end
