defmodule LightClientTestRunner do
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.Utils.Diff
  use ExUnit.CaseTemplate
  use TestRunner

  @moduledoc """
  Runner for LightClient test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/light_client
  """

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    # "single_merkle_proof",
    "sync",
    "update_ranking",
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    object =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/object.ssz_snappy",
        SszTypes.BeaconState
      )

    %{leaf: leaf, leaf_index: leaf_index, branch: branch} =
      YamlElixir.read_from_file!(case_dir <> "/proof.yaml")
      |> SpecTestUtils.sanitize_yaml()

    handle(testcase.handler, leaf, leaf_index, branch, object)
  end

  defp handle("single_merkle_proof", leaf, leaf_index, branch, object) do
    object_root = Ssz.hash_tree_root!(object)
    res = Predicates.is_valid_merkle_branch?(
      leaf,
      branch,
      Constants.deposit_contract_tree_depth() + 1,
      leaf_index,
      object_root
    )
    assert Diff.diff(true, res) == :unchanged
  end
end
