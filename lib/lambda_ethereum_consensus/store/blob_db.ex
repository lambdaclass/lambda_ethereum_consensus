defmodule LambdaEthereumConsensus.Store.BlobDb do
  @moduledoc """
  Storage and retrieval of blobs.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias Types.BlobSidecar

  @blob_prefix "blob"

  @spec store_blob(BlobSidecar.t()) :: :ok
  def store_blob(%BlobSidecar{signed_block_header: %{message: block}} = blob) do
    block_root = Ssz.hash_tree_root!(block)
    {:ok, encoded_blob} = Ssz.to_ssz(blob)

    key = blob_key(block_root, blob.index)
    Db.put(key, encoded_blob)
  end

  @spec get_blob(Types.root(), Types.blob_index()) ::
          {:ok, BlobSidecar.t()} | {:error, String.t()} | :not_found
  def get_blob(block_root, blob_index) do
    key = blob_key(block_root, blob_index)

    with {:ok, signed_block} <- Db.get(key) do
      Ssz.from_ssz(signed_block, BlobSidecar)
    end
  end

  defp blob_key(block_root, blob_index), do: @blob_prefix <> block_root <> <<blob_index>>
end
