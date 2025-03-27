defmodule LambdaEthereumConsensus.Store.Blobs do
  @moduledoc """
  Interface to `Store.Blobs`.
  """
  require Logger

  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.P2P.BlobDownloader
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BlockInfo

  def process_blobs(store, {:ok, blobs}), do: {:ok, add_blobs(store, blobs)}

  def process_blobs(store, {:error, reason}) do
    # We might want to declare a block invalid here.
    Logger.error("[PendingBlocks] Error downloading blobs: #{inspect(reason)}")
    {:ok, store}
  end

  def add_blob(store, blob), do: add_blobs(store, [blob])

  # To be used when a series of blobs are downloaded. Stores each blob.
  # If there are blocks that can be processed, does so immediately.
  def add_blobs(store, blobs) do
    blobs
    |> Enum.map(&BlobDb.store_blob/1)
    |> Enum.uniq()
    |> Enum.reduce(store, fn root, store ->
      with %BlockInfo{status: :download_blobs} = block_info <- Blocks.get_block_info(root),
           [] <- missing_blobs(block_info) do
        block_info
        |> Blocks.change_status(:pending)
        |> then(&PendingBlocks.process_block_and_check_children(store, &1))
      else
        _ ->
          store
      end
    end)
  end

  @spec missing_blobs(BlockInfo.t()) :: [Types.BlobIdentifier.t()]
  def missing_blobs(%BlockInfo{root: root, signed_block: signed_block}) do
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

  def schedule_blob_download(missing_blobs, retries) do
    BlobDownloader.request_blobs_by_root(
      missing_blobs,
      &process_blobs/2,
      retries
    )

    :ok
  end
end
