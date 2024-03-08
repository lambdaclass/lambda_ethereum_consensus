defmodule KzgTestRunner do
  @moduledoc """
  Runner for KZG test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/kzg
  """

  use ExUnit.CaseTemplate
  use TestRunner

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    # "blob_to_kzg_commitment"
    # "compute_kzg_proof",
    # "verify_kzg_proof",
    # "compute_blob_kzg_proof",
    # "verify_blob_kzg_proof",
    # "verify_blob_kzg_proof_batch"
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
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.blob_to_kzg_commitment(blob)
        assert result == :error

      output ->
        assert {:ok, commitment} = Kzg.blob_to_kzg_commitment(blob)
        assert commitment == output
    end
  end

  defp handle_case("compute_kzg_proof", %{blob: blob, z: z}, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.compute_kzg_proof(blob, z)
        assert result == :error

      output ->
        assert {:ok, proof} = Kzg.compute_kzg_proof(blob, z)
        assert proof |> Tuple.to_list() == output
    end
  end

  defp handle_case("compute_blob_kzg_proof", %{blob: blob, commitment: commitment}, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.compute_blob_kzg_proof(blob, commitment)
        assert result == :error

      output ->
        assert {:ok, kzg_proof} = Kzg.compute_blob_kzg_proof(blob, commitment)
        assert kzg_proof == output
    end
  end

  defp handle_case(
         "verify_kzg_proof",
         %{commitment: commitment, z: z, y: y, proof: proof},
         output
       ) do
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.verify_kzg_proof(commitment, z, y, proof)
        assert result == :error

      output ->
        assert {:ok, status} = Kzg.verify_kzg_proof(commitment, z, y, proof)
        assert status == output
    end
  end

  defp handle_case(
         "verify_blob_kzg_proof",
         %{blob: blob, commitment: commitment, proof: proof},
         output
       ) do
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.verify_blob_kzg_proof(blob, commitment, proof)
        assert result == :error

      output ->
        assert {:ok, status} = Kzg.verify_blob_kzg_proof(blob, commitment, proof)
        assert status == output
    end
  end

  defp handle_case(
         "verify_blob_kzg_proof_batch",
         %{blobs: blobs, commitments: commitments, proofs: proofs},
         output
       ) do
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.verify_blob_kzg_proof_batch(blobs, commitments, proofs)
        assert result == :error

      output ->
        assert {:ok, status} = Kzg.verify_blob_kzg_proof_batch(blobs, commitments, proofs)
        assert status == output
    end
  end
end
