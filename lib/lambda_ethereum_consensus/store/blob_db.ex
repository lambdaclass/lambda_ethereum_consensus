defmodule LambdaEthereumConsensus.Store.BlobDb do
  @moduledoc """
  Storage and retrieval of blobs.
  """
  require Logger

  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.Blobdata
  alias Types.BlobSidecar

  @blob_sidecar_prefix "blob_sidecar"
  @blobdata_prefix "blobdata"
  @block_root_prefix "block_root"

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

    block_root_key = block_root_key(block_header.slot, blob.index)
    Db.put(block_root_key, block_root)
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

  @spec get_blob_by_slot_index(non_neg_integer(), non_neg_integer()) ::
          {:ok, BlobSidecar.t()} | {:error, String.t()} | :not_found
  def get_blob_by_slot_index(slot, index) do
    block_root_key = block_root_key(slot, index)

    with {:ok, block_root} <- Db.get(block_root_key) do
      get_blob_sidecar(block_root, index)
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

  @spec prune_blobs_older_than(non_neg_integer()) :: :ok | {:error, String.t()} | :not_found
  def prune_blobs_older_than(slot) do
    Logger.info("[BlobDb] Pruning started.", slot: slot)
    last_finalized_key = slot |> block_root_key(0)

    with {:ok, it} <- Db.iterate(),
         {:ok, @block_root_prefix <> _, _value} <-
           Exleveldb.iterator_move(it, last_finalized_key),
         {:ok, keys_to_remove} <- get_block_root_keys_to_remove(it),
         :ok <- Exleveldb.iterator_close(it) do
      keys_to_remove |> Enum.each(&remove_blob_by_block_root_key/1)

      Logger.info("[BlobDb] Pruning finished. #{length(keys_to_remove)} blobs removed.")
    end
  end

  @spec get_block_root_keys_to_remove(list(binary()), :eleveldb.itr_ref()) ::
          {:ok, list(binary())}
  defp get_block_root_keys_to_remove(keys_to_remove \\ [], iterator) do
    case Exleveldb.iterator_move(iterator, :prev) do
      {:ok, <<@block_root_prefix, slot::unsigned-size(64), index::binary>> = block_root_key,
       _root} ->
        [block_root_key | keys_to_remove] |> get_block_root_keys_to_remove(iterator)

      _ ->
        {:ok, keys_to_remove}
    end
  end

  @spec remove_blob_by_block_root_key(binary()) :: :ok | :not_found
  defp remove_blob_by_block_root_key(block_root_key) do
    <<@block_root_prefix, _slot::unsigned-size(64), index>> =
      block_root_key

    with {:ok, block_root} <- Db.get(block_root_key) do
      key_blob = blob_sidecar_key(block_root, index)
      key_data = blobdata_key(block_root, index)

      Db.delete(block_root_key)
      Db.delete(key_blob)
      Db.delete(key_data)
    end
  end

  defp blob_sidecar_key(block_root, blob_index),
    do: @blob_sidecar_prefix <> block_root <> <<blob_index>>

  defp blobdata_key(block_root, blob_index), do: @blobdata_prefix <> block_root <> <<blob_index>>

  defp block_root_key(blob_slot, blob_index) do
    Utils.get_key(@block_root_prefix, blob_slot) <> <<blob_index>>
  end
end
