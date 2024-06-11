defmodule LambdaEthereumConsensus.Beacon.PendingBlocks do
  @moduledoc """
    Manages pending blocks and performs validations before adding them to the fork choice.

    The main purpose of this module is making sure that a blocks parent is already in the fork choice. If it's not, it will request it to the block downloader.
  """
  require Logger

  alias LambdaEthereumConsensus.ForkChoice
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

  @doc """
  If the block is not present, it will be stored as pending.

  In case it's ready to be processed
  (the parent is present and already transitioned), then the block's state transition will be
  calculated, resulting in a new saved block.

  If the new state enables older blocks that were pending to be processed, they will be processed
  immediately.
  """
  @spec add_block(SignedBeaconBlock.t()) :: :ok
  def add_block(signed_block) do
    block_info = BlockInfo.from_block(signed_block)

    # If the block is new or was to be downloaded, we store it.
    loaded_block = Blocks.get_block_info(block_info.root)

    if is_nil(loaded_block) or loaded_block.status == :download do
      if Enum.empty?(missing_blobs(block_info)) do
        block_info
      else
        block_info |> BlockInfo.change_status(:download_blobs)
      end
      |> Blocks.new_block_info()

      process_block(block_info)
    end
  end

  @doc """
  Iterates through the pending blocks and adds them to the fork choice if their parent is already in the fork choice.
  """
  @spec handle_info(atom(), state()) :: {:noreply, state()}
  def handle_info(:process_blocks, _state) do
    process_blocks()
    {:noreply, nil}
  end

  def handle_info(:download_blobs, _state) do
    case Blocks.get_blocks_with_status(:download_blobs) do
      {:ok, blocks_with_missing_blobs} ->
        blocks_with_blobs =
          blocks_with_missing_blobs
          |> Enum.sort_by(fn %BlockInfo{} = block_info -> block_info.signed_block.message.slot end)
          |> Enum.take(16)

        blobs_to_download = Enum.flat_map(blocks_with_blobs, &missing_blobs/1)

        downloaded_blobs =
          blobs_to_download
          |> BlobDownloader.request_blobs_by_root()
          |> case do
            {:ok, blobs} ->
              blobs

            {:error, reason} ->
              Logger.debug("Blob download failed: '#{reason}'")
              []
          end

        Enum.each(downloaded_blobs, &BlobDb.store_blob/1)

        # TODO: is it not possible that blobs were downloaded for one and not for another?
        if length(downloaded_blobs) == length(blobs_to_download) do
          Enum.each(blocks_with_blobs, &Blocks.change_status(&1, :pending))
        end
    end

    {:noreply, nil}
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

  defp process_block(block_info) do
    parent_root = block_info.signed_block.message.parent_root

    case Blocks.get_block_info(parent_root) do
      nil ->
        Blocks.add_block_to_download(parent_root)

      %BlockInfo{status: :invalid} ->
        Blocks.change_status(block_info, :invalid)

      %BlockInfo{status: :transitioned} ->
        case ForkChoice.on_block(block_info) do
          :ok ->
            Blocks.change_status(block_info, :transitioned)
            # Block is valid. We immediately check if we can process another block.
            process_blocks()

          {:error, reason} ->
            Logger.error("[PendingBlocks] Saving block as invalid #{reason}",
              slot: block_info.signed_block.message.slot,
              root: block_info.root
            )

            Blocks.change_status(block_info, :invalid)
        end

      _other ->
        :ok
    end
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
