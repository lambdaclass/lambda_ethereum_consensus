defmodule Kzg do
  @moduledoc """
  KZG functions
  """
  use Rustler, otp_app: :lambda_ethereum_consensus, crate: "kzg_nif"

  @type commitment :: <<_::384>>
  @type proof :: <<_::768>>

  @spec blob_to_kzg_commitment(Types.blob()) :: {:ok, commitment()} | {:error, binary()}
  def blob_to_kzg_commitment(_blob) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec compute_kzg_proof(Types.blob(), Types.bytes32()) ::
          {:ok, {proof(), Types.bytes32()}} | {:error, binary()}
  def compute_kzg_proof(_blob, _z) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec verify_kzg_proof(
          commitment(),
          Types.bytes32(),
          Types.bytes32(),
          proof()
        ) ::
          {:ok, boolean} | {:error, binary()}
  def verify_kzg_proof(_kzg_commitment, _z, _y, _kzg_proof) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec compute_blob_kzg_proof(Types.blob(), commitment()) ::
          {:ok, proof()} | {:error, binary()}
  def compute_blob_kzg_proof(_blob, _kzg_commitment) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec verify_blob_kzg_proof(Types.blob(), commitment(), proof()) ::
          {:ok, boolean} | {:error, binary()}
  def verify_blob_kzg_proof(_blob, _kzg_commitment, _kzg_proof) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @spec verify_blob_kzg_proof_batch(
          list(Types.blob()),
          list(commitment()),
          list(proof())
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
          list(commitment()),
          list(proof())
        ) :: boolean()
  def blob_kzg_proof_batch_valid?(blobs, kzg_commitments, kzg_proofs) do
    case verify_blob_kzg_proof_batch(blobs, kzg_commitments, kzg_proofs) do
      {:ok, result} -> result
      {:error, _} -> false
    end
  end
end
