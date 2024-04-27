defmodule Kzg do
  @moduledoc """
  KZG functions
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "kzg_nif"

  # Max size: BYTES_PER_FIELD_ELEMENT * FIELD_ELEMENTS_PER_BLOB
  @type blob :: binary
  @type kzg_commitment :: bytes48
  @type kzg_proof :: bytes48

  @spec blob_to_kzg_commitment(Types.blob()) :: {:ok, Types.kzg_commitment()} | {:error, binary()}
  def blob_to_kzg_commitment(_blob) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec compute_kzg_proof(Types.blob(), Types.bytes32()) ::
          {:ok, {Types.kzg_proof(), Types.bytes32()}} | {:error, binary()}
  def compute_kzg_proof(_blob, _z) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec verify_kzg_proof(
          Types.kzg_commitment(),
          Types.bytes32(),
          Types.bytes32(),
          Types.kzg_proof()
        ) ::
          {:ok, boolean} | {:error, binary()}
  def verify_kzg_proof(_kzg_commitment, _z, _y, _kzg_proof) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec compute_blob_kzg_proof(Types.blob(), Types.kzg_commitment()) ::
          {:ok, Types.kzg_proof()} | {:error, binary()}
  def compute_blob_kzg_proof(_blob, _kzg_commitment) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec verify_blob_kzg_proof(Types.blob(), Types.kzg_commitment(), Types.kzg_proof()) ::
          {:ok, boolean} | {:error, binary()}
  def verify_blob_kzg_proof(_blob, _kzg_commitment, _kzg_proof) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec verify_blob_kzg_proof_batch(
          list(Types.blob()),
          list(Types.kzg_commitment()),
          list(Types.kzg_proof())
        ) ::
          {:ok, boolean} | {:error, binary()}
  def verify_blob_kzg_proof_batch(_blobs, _kzg_commitments, _kzg_proofs) do
    :erlang.nif_error(:nif_not_loaded)
  end

  ################
  ### Wrappers ###
  ################

  @spec blob_kzg_proof_batch_valid?(
          list(Types.blob()),
          list(Types.kzg_commitment()),
          list(Types.kzg_proof())
        ) :: boolean()
  def blob_kzg_proof_batch_valid?(blobs, kzg_commitments, kzg_proofs) do
    case verify_blob_kzg_proof_batch(blobs, kzg_commitments, kzg_proofs) do
      {:ok, result} -> result
      {:error, _} -> false
    end
  end
end
