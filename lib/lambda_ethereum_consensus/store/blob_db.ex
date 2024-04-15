defmodule LambdaEthereumConsensus.Store.BlobDb do
  @moduledoc """
  Storage and retrieval of blobs.
  """
  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.Store.Db
  alias Types.Blobdata
  alias Types.BlobSidecar

  @blob_sidecar_prefix "blob_sidecar"
  @blobdata_prefix "blobdata"

  @spec store_blob(BlobSidecar.t()) :: :ok
  def store_blob(%BlobSidecar{signed_block_header: %{message: block_header}} = blob) do
    block_root = Ssz.hash_tree_root!(block_header)
    {:ok, encoded_blob} = Ssz.to_ssz(blob)

    key = blob_sidecar_key(block_root, blob.index)
    Db.put(key, encoded_blob)

    {:ok, encoded_blobdata} =
      SszEx.encode(%Blobdata{blob: blob.blob, proof: blob.kzg_proof}, Blobdata)

    key = blobdata_key(block_root, blob.index)
    Db.put(key, encoded_blobdata)
  end

  # TODO: this is only used for tests
  @spec store_blob_with_proof(Types.root(), Types.uint64(), Types.blob(), Types.kzg_proof()) ::
          :ok
  def store_blob_with_proof(block_root, index, blob, proof) do
    {:ok, encoded_blobdata} = SszEx.encode(%Blobdata{blob: blob, proof: proof}, Blobdata)
    key = blobdata_key(block_root, index)
    Db.put(key, encoded_blobdata)
  end

  @spec get_blob_sidecar(Types.root(), Types.blob_index()) ::
          {:ok, BlobSidecar.t()} | {:error, String.t()} | :not_found
  def get_blob_sidecar(block_root, blob_index) do
    key = blob_sidecar_key(block_root, blob_index)

    with {:ok, signed_block} <- Db.get(key) do
      Ssz.from_ssz(signed_block, BlobSidecar)
    end
  end

  @spec get_blob_with_proof(Types.root(), Types.blob_index()) ::
          {:ok, {Types.blob(), Types.kzg_proof()}} | {:error, String.t()} | :not_found
  def get_blob_with_proof(block_root, blob_index) do
    key = blobdata_key(block_root, blob_index)

    with {:ok, encoded_blobdata} <- Db.get(key),
         {:ok, blobdata} <- SszEx.decode(encoded_blobdata, Blobdata) do
      %{blob: blob, proof: proof} = blobdata
      {:ok, {blob, proof}}
    end
  end

  defp blob_sidecar_key(block_root, blob_index),
    do: @blob_sidecar_prefix <> block_root <> <<blob_index>>

  defp blobdata_key(block_root, blob_index), do: @blobdata_prefix <> block_root <> <<blob_index>>
end
