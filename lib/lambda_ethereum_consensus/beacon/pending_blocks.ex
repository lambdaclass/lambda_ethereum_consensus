defmodule LambdaEthereumConsensus.Beacon.PendingBlocks do
  @moduledoc """
    Manages pending blocks and performs validations before adding them to the fork choice.

    The main purpose of this module is making sure that a blocks parent is already in the fork choice. If it's not, it will request it to the block downloader.
  """
  require Logger

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.BlockDownloader

  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.P2P.BlobDownloader
  alias LambdaEthereumConsensus.Store.BlobDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BlockInfo
  alias Types.SignedBeaconBlock

  @type block_status :: :pending | :invalid | :download | :download_blobs | :unknown
  @type block_info ::
          {SignedBeaconBlock.t(), :pending | :download_blobs}
          | {nil, :invalid | :download}
  @type state :: nil

  @download_retries 100

  @doc """
  If the block is not present, it will be stored as pending.

  In case it's ready to be processed
  (the parent is present and already transitioned), then the block's state transition will be
  calculated, resulting in a new saved block.

  If the new state enables older blocks that were pending to be processed, they will be processed
  immediately.

  If blobs are missing, they will be requested.
  """
  @spec add_block(SignedBeaconBlock.t()) :: :ok
  def add_block(signed_block) do
    block_info = BlockInfo.from_block(signed_block)
    loaded_block = Blocks.get_block_info(block_info.root)

    # If the block is new or was to be downloaded, we store it.
    if is_nil(loaded_block) or loaded_block.status == :download do
      missing_blobs = missing_blobs(block_info)

      if Enum.empty?(missing_blobs) do
        Blocks.new_block_info(block_info)
        process_block_and_check_children(block_info)
      else
        BlobDownloader.request_blobs_by_root(missing_blobs, &process_blobs/1, @download_retries)

        block_info
        |> BlockInfo.change_status(:download_blobs)
        |> Blocks.new_block_info()
      end
    end
  end

  ##########################
  ### Private Functions
  ##########################

  defp process_blocks() do
    case Blocks.get_blocks_with_status(:pending) do
      {:ok, blocks} ->
        blocks
        |> Enum.sort_by(fn %BlockInfo{} = block_info -> block_info.signed_block.message.slot end)
        |> Enum.each(&process_block/1)

      {:error, reason} ->
        Logger.error(
          "[Pending Blocks] Failed to get pending blocks to process. Reason: #{reason}"
        )
    end
  end

  # Processes a block. If it was transitioned or declared invalid, then process_blocks
  # is called to check if there's any children that can now be processed. This function
  # is only to be called when a new block is saved as pending, not when processing blocks
  # in batch, to avoid unneeded recursion.
  defp process_block_and_check_children(block_info) do
    if process_block(block_info) in [:transitioned, :invalid] do
      process_blocks()
    end
  end

  defp process_block(block_info) do
    if block_info.status != :pending do
      Logger.error("Called process block for a block that's not ready: #{block_info}")
    end

    parent_root = block_info.signed_block.message.parent_root

    case Blocks.get_block_info(parent_root) do
      nil ->
        Logger.debug("[PendingBlocks] Add parent to download #{inspect(parent_root)}")
        Blocks.add_block_to_download(parent_root)

        BlockDownloader.request_blocks_by_root(
          [parent_root],
          fn result ->
            process_downloaded_block(result)
          end,
          @download_retries
        )

        Metrics.block_relationship(
          parent_root,
          block_info.root
        )

        :download_pending

      %BlockInfo{status: :invalid} ->
        Blocks.change_status(block_info, :invalid)
        :invalid

      %BlockInfo{status: :transitioned} ->
        case ForkChoice.on_block(block_info) do
          :ok ->
            Blocks.change_status(block_info, :transitioned)
            :transitioned

          {:error, reason} ->
            Logger.error("[PendingBlocks] Saving block as invalid #{reason}",
              slot: block_info.signed_block.message.slot,
              root: block_info.root
            )

            Blocks.change_status(block_info, :invalid)
            :invalid
        end

      _other ->
        :ok
    end
  end

  defp process_downloaded_block({:ok, [block]}) do
    Libp2pPort.add_block(block)
  end

  defp process_downloaded_block({:error, reason}) do
    Logger.error("Error downloading block: #{inspect(reason)}")

    # We might want to declare a block invalid here.
  end

  defp process_blobs({:ok, blobs}), do: add_blobs(blobs)

  defp process_blobs({:error, reason}) do
    Logger.error("Error downloading blobs: #{inspect(reason)}")

    # We might want to declare a block invalid here.
  end

  # To be used when a series of blobs are downloaded. Stores each blob.
  # If there are blocks that can be processed, does so immediately.
  defp add_blobs(blobs) do
    blobs
    |> Enum.map(&BlobDb.store_blob/1)
    |> Enum.uniq()
    |> Enum.each(fn root ->
      with %BlockInfo{} = block_info <- Blocks.get_block_info(root) do
        # TODO: add a new missing blobs call if some blobs are still missing for a block.
        if Enum.empty?(missing_blobs(block_info)) do
          block_info
          |> Blocks.change_status(:pending)
          |> process_block_and_check_children()
        end
      end
    end)
  end

  @spec missing_blobs(BlockInfo.t()) :: [Types.BlobIdentifier.t()]
  defp missing_blobs(%BlockInfo{root: root, signed_block: signed_block}) do
    signed_block.message.body.blob_kzg_commitments
    |> Stream.with_index()
    |> Enum.filter(&blob_needs_download?(&1, root))
    |> Enum.map(&%Types.BlobIdentifier{block_root: root, index: elem(&1, 1)})
  end

  defp blob_needs_download?({commitment, index}, block_root) do
    case BlobDb.get_blob_sidecar(block_root, index) do
      {:ok, %{kzg_commitment: ^commitment}} ->
        false

      _ ->
        true
    end
  end
end
