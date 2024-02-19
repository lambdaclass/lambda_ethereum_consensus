defmodule KzgTestRunner do
  @moduledoc """
  Runner for KZG test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/kzg
  """

  use ExUnit.CaseTemplate
  use TestRunner

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    # "blob_to_kzg_commitment"
    "compute_kzg_proof",
    "verify_kzg_proof",
    "compute_blob_kzg_proof",
    "verify_blob_kzg_proof",
    "verify_blob_kzg_proof_batch",
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    %{input: input, output: output} =
      YamlElixir.read_from_file!(case_dir <> "/data.yaml")
      |> SpecTestUtils.sanitize_yaml()

    handle_case(testcase.handler, input, output)
  end

  defp handle_case("blob_to_kzg_commitment", %{blob: blob}, output) do
    {:ok, commitment} = Kzg.blob_to_kzg_commitment(blob)
    assert commitment == output
  end
end
