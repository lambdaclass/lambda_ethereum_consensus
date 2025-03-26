defmodule LambdaEthereumConsensus.Beacon.PendingBlocks do
  @moduledoc """
    Manages pending blocks and performs validations before adding them to the fork choice.

    The main purpose of this module is making sure that a blocks parent is already in the fork choice. If it's not, it will request it to the block downloader.
  """
  require Logger

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.P2P.BlobDownloader
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.Store.Blobs
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Utils
  alias Types.BlockInfo
  alias Types.SignedBeaconBlock
  alias Types.Store

  @type block_status ::
          :transitioned | :pending | :invalid | :download | :download_blobs | :unknown
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
  @spec add_block(Store.t(), SignedBeaconBlock.t()) :: Store.t()
  def add_block(store, signed_block) do
    block_info = BlockInfo.from_block(signed_block)
    loaded_block = Blocks.get_block_info(block_info.root)
    log_md = [slot: signed_block.message.slot, root: block_info.root]

    # If the block is new or was to be downloaded, we store it.
    if is_nil(loaded_block) or loaded_block.status == :download do
      missing_blobs = Blobs.missing_blobs(block_info)

      if Enum.empty?(missing_blobs) do
        Logger.debug("[PendingBlocks] No missing blobs for block, process it", log_md)
        Blocks.new_block_info(block_info)
        process_block_and_check_children(store, block_info)
      else
        Logger.debug("[PendingBlocks] Missing blobs for block, scheduling download", log_md)

        BlobDownloader.request_blobs_by_root(
          missing_blobs,
          &Blobs.process_blobs/2,
          @download_retries
        )

        block_info
        |> BlockInfo.change_status(:download_blobs)
        |> Blocks.new_block_info()

        store
      end
    else
      store
    end
  end

  @doc """
  Sends any blocks that are ready to block processing. This should usually be called only by this
  module after receiving a new block, but there are some other cases like at node startup, as there
  may be pending blocks from prior executions.
  """
  def process_blocks(store) do
    case Blocks.get_blocks_with_status(:pending) do
      {:ok, blocks} ->
        blocks
        |> Enum.sort_by(fn %BlockInfo{} = block_info -> block_info.signed_block.message.slot end)
        # Could we process just one/a small amount of blocks at a time? would it make more sense?
        |> Enum.reduce(store, fn block_info, store ->
          {store, _state} = process_block(store, block_info)
          store
        end)

      {:error, reason} ->
        Logger.error(
          "[Pending Blocks] Failed to get pending blocks to process. Reason: #{reason}"
        )

        store
    end
  end

  # Processes a block. If it was transitioned or declared invalid, then process_blocks
  # is called to check if there's any children that can now be processed. This function
  # is only to be called when a new block is saved as pending, not when processing blocks
  # in batch, to avoid unneeded recursion.
  def process_block_and_check_children(store, block_info) do
    case process_block(store, block_info) do
      {store, result} when result in [:transitioned, :invalid] -> process_blocks(store)
      {store, _other} -> store
    end
  end

  ##########################
  ### Private Functions
  ##########################

  defp process_block(store, %BlockInfo{signed_block: %{message: message}} = block_info) do
    if block_info.status != :pending do
      Logger.error(
        "[PendingBlocks] Called process block for a block that's not ready: #{block_info}"
      )
    end

    log_md = [slot: message.slot, root: block_info.root]
    parent_root = message.parent_root

    Logger.debug(
      "[PendingBlocks] Processing block, parent: #{Utils.format_binary(parent_root)}",
      log_md
    )

    case Blocks.get_block_info(parent_root) do
      nil ->
        Logger.debug(
          "[PendingBlocks] Add parent with root: #{Utils.format_shorten_binary(parent_root)} to download",
          log_md
        )

        Blocks.add_block_to_download(parent_root)

        BlockDownloader.request_blocks_by_root(
          [parent_root],
          &process_downloaded_block/2,
          @download_retries
        )

        Metrics.block_relationship(
          parent_root,
          block_info.root
        )

        {store, :download_pending}

      %BlockInfo{status: :invalid} ->
        Logger.warning(
          "[PendingBlocks] Parent block with root:#{Utils.format_shorten_binary(parent_root)} is invalid, making this block also invalid",
          log_md
        )

        Blocks.change_status(block_info, :invalid)
        {store, :invalid}

      %BlockInfo{status: :transitioned} ->
        case ForkChoice.on_block(store, block_info) do
          {:ok, store} ->
            Logger.debug("[PendingBlocks] Block transitioned after ForkChoice.on_block/2", log_md)
            Blocks.change_status(block_info, :transitioned)
            {store, :transitioned}

          {:error, reason, store} ->
            Logger.error(
              "[PendingBlocks] Saving block as invalid after ForkChoice.on_block/2 error: #{reason}",
              log_md
            )

            Blocks.change_status(block_info, :invalid)
            {store, :invalid}
        end

      _other ->
        {store, :ok}
    end
  end

  defp process_downloaded_block(store, {:ok, [block]}) do
    {:ok, add_block(store, block)}
  end

  defp process_downloaded_block(store, {:error, reason}) do
    # We might want to declare a block invalid here.
    Logger.error("[PendingBlocks] Error downloading block: #{inspect(reason)}")
    {:ok, store}
  end
end
