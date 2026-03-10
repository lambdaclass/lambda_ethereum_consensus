defmodule KzgTestRunner do
  @moduledoc """
  Runner for KZG test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/kzg
  """

  use ExUnit.CaseTemplate
  use TestRunner

  # Fiat-Shamir domain separator for cell KZG batch challenges (16 bytes)
  @random_challenge_kzg_cell_batch_domain "RCKZGCBATCH__V1_"
  # Fiat-Shamir domain separator for single blob KZG challenges (16 bytes)
  @fiat_shamir_protocol_domain "FSBLOBVERIFY_V1_"
  # BLS12-381 scalar field modulus
  @bls_modulus 52_435_875_175_126_190_479_447_740_508_185_965_837_690_552_500_527_637_822_603_658_699_938_581_184_513
  # KZG preset constants (fixed across all configs)
  @field_elements_per_blob 4096
  @field_elements_per_cell 64

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

  defp handle_case("compute_cells_and_kzg_proofs", %{blob: blob}, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.compute_cells_and_kzg_proofs(blob)
        assert result == :error

      output ->
        assert {:ok, {cells, proofs}} = Kzg.compute_cells_and_kzg_proofs(blob)
        assert [cells, proofs] == output
    end
  end

  defp handle_case("compute_cells", %{blob: blob}, output) do
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.compute_cells_and_kzg_proofs(blob)
        assert result == :error

      output ->
        assert {:ok, {cells, _proofs}} = Kzg.compute_cells_and_kzg_proofs(blob)
        assert cells == output
    end
  end

  defp handle_case(
         "recover_cells_and_kzg_proofs",
         %{cell_indices: cell_indices, cells: cells},
         output
       ) do
    case output do
      nil ->
        assert {result, _error_msg} = Kzg.recover_cells_and_kzg_proofs(cell_indices, cells)
        assert result == :error

      output ->
        assert {:ok, {recovered_cells, recovered_proofs}} =
                 Kzg.recover_cells_and_kzg_proofs(cell_indices, cells)

        assert [recovered_cells, recovered_proofs] == output
    end
  end

  defp handle_case(
         "verify_cell_kzg_proof_batch",
         %{commitments: commitments, cell_indices: cell_indices, cells: cells, proofs: proofs},
         output
       ) do
    case output do
      nil ->
        assert {result, _error_msg} =
                 Kzg.verify_cell_kzg_proof_batch(commitments, cell_indices, cells, proofs)

        assert result == :error

      output ->
        assert {:ok, status} =
                 Kzg.verify_cell_kzg_proof_batch(commitments, cell_indices, cells, proofs)

        assert status == output
    end
  end

  # compute_challenge: Fiat-Shamir challenge for a single blob+commitment (EIP-4844/Deneb spec)
  defp handle_case("compute_challenge", %{blob: blob, commitment: commitment}, output) do
    challenge = compute_blob_challenge(blob, commitment)
    assert challenge == output
  end

  defp handle_case(
         "compute_verify_cell_kzg_proof_batch_challenge",
         %{
           commitments: commitments,
           commitment_indices: commitment_indices,
           cell_indices: cell_indices,
           cosets_evals: cosets_evals,
           proofs: proofs
         },
         output
       ) do
    challenge =
      compute_challenge(commitments, commitment_indices, cell_indices, cosets_evals, proofs)

    assert challenge == output
  end

  # Computes the Fiat-Shamir challenge for verify_cell_kzg_proof_batch.
  # Implements compute_verify_cell_kzg_proof_batch_challenge from the Fulu spec:
  # domain || FIELD_ELEMENTS_PER_BLOB || FIELD_ELEMENTS_PER_CELL ||
  # len(commitments) || len(cell_indices) || commitments ||
  # [commitment_index || cell_index || coset_evals || proof] per entry
  # Result: SHA-256(input) as big-endian integer mod BLS_MODULUS, padded to 32 bytes.
  defp compute_challenge(commitments, commitment_indices, cell_indices, cosets_evals, proofs) do
    per_item =
      [commitment_indices, cell_indices, cosets_evals, proofs]
      |> Enum.zip()
      |> Enum.map_join("", fn {ci, ki, evals, proof} ->
        <<ci::big-unsigned-64>> <>
          <<ki::big-unsigned-64>> <>
          Enum.join(evals) <>
          proof
      end)

    hash_input =
      @random_challenge_kzg_cell_batch_domain <>
        <<@field_elements_per_blob::big-unsigned-64>> <>
        <<@field_elements_per_cell::big-unsigned-64>> <>
        <<length(commitments)::big-unsigned-64>> <>
        <<length(cell_indices)::big-unsigned-64>> <>
        Enum.join(commitments) <>
        per_item

    hash_value = :crypto.hash(:sha256, hash_input)
    field_int = :binary.decode_unsigned(hash_value, :big)
    reduced = rem(field_int, @bls_modulus)
    <<reduced::big-unsigned-256>>
  end

  # Computes the Fiat-Shamir evaluation challenge z for a single blob+commitment.
  # Implements compute_challenge from the c-kzg reference implementation (eip4844.c):
  # domain || hi_u64(0) || lo_u64(FIELD_ELEMENTS_PER_BLOB) || blob || commitment
  # The polynomial degree is encoded as a 128-bit big-endian integer split across two u64s.
  # Result: SHA-256(input) as big-endian integer mod BLS_MODULUS, padded to 32 bytes.
  defp compute_blob_challenge(blob, commitment) do
    hash_input =
      @fiat_shamir_protocol_domain <>
        <<0::big-unsigned-64>> <>
        <<@field_elements_per_blob::big-unsigned-64>> <>
        blob <>
        commitment

    hash_value = :crypto.hash(:sha256, hash_input)
    field_int = :binary.decode_unsigned(hash_value, :big)
    reduced = rem(field_int, @bls_modulus)
    <<reduced::big-unsigned-256>>
  end
end
