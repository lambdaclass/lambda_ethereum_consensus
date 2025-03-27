defmodule LambdaEthereumConsensus.Store.Blobs do
  @moduledoc """
  Interface to `Store.Blobs`.
  """
  require Logger

  alias LambdaEthereumConsensus.Store.BlobDb
  alias Types.BlockInfo

  def add_blob(blob), do: add_blobs([blob])

  # To be used when a series of blobs are downloaded. Stores each blob.
  def add_blobs(blobs) do
    blobs
    |> Enum.map(&BlobDb.store_blob/1)
    |> Enum.uniq()
  end

  @spec missing_for_block(BlockInfo.t()) :: [Types.BlobIdentifier.t()]
  def missing_for_block(%BlockInfo{root: root, signed_block: signed_block}) do
    signed_block.message.body.blob_kzg_commitments
    |> Stream.with_index()
    |> Enum.filter(&present?(&1, root))
    |> Enum.map(&%Types.BlobIdentifier{block_root: root, index: elem(&1, 1)})
  end

  defp present?({commitment, index}, block_root) do
    case BlobDb.get_blob_sidecar(block_root, index) do
      {:ok, %{kzg_commitment: ^commitment}} ->
        false

      _ ->
        true
    end
  end
end
