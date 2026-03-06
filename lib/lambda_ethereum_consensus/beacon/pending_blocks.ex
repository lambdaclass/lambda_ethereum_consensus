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
  alias LambdaEthereumConsensus.P2P.DataColumnDownloader
  alias LambdaEthereumConsensus.StateTransition.DasCore
  alias LambdaEthereumConsensus.Store.Blobs
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.DataColumns
  alias LambdaEthereumConsensus.Utils
  alias Types.BlockInfo
  alias Types.SignedBeaconBlock
  alias Types.Store

  @type block_status ::
          :transitioned
          | :pending
          | :invalid
          | :download
          | :download_blobs
          | :download_columns
          | :unknown
  @type block_info ::
          {SignedBeaconBlock.t(), :pending | :download_blobs | :download_columns}
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

  On Electra: if blobs are missing, they will be requested.
  On Fulu: if custody data columns are missing, they will be requested.
  """
  @spec add_block(Store.t(), SignedBeaconBlock.t()) :: Store.t()
  def add_block(store, signed_block) do
    block_info = BlockInfo.from_block(signed_block)
    loaded_block = Blocks.get_block_info(block_info.root)
    log_md = [slot: signed_block.message.slot, root: block_info.root]

    # If the block is new or was to be downloaded, we store it.
    if is_nil(loaded_block) or loaded_block.status == :download do
      if HardForkAliasInjection.fulu?() do
        add_block_fulu(store, block_info, log_md)
      else
        add_block_electra(store, block_info, log_md)
      end
    else
      store
    end
  end

  defp add_block_electra(store, block_info, log_md) do
    missing_blobs = Blobs.missing_for_block(block_info)

    if Enum.empty?(missing_blobs) do
      Logger.debug("[PendingBlocks] No missing blobs for block, process it", log_md)
      Blocks.new_block_info(block_info)
      process_block_and_check_children(store, block_info)
    else
      Logger.debug("[PendingBlocks] Missing blobs for block, scheduling download", log_md)

      BlobDownloader.request_blobs_by_root(
        missing_blobs,
        &process_blobs/2,
        @download_retries
      )

      block_info
      |> BlockInfo.change_status(:download_blobs)
      |> Blocks.new_block_info()

      store
    end
  end

  defp add_block_fulu(store, block_info, log_md) do
    missing_columns =
      DataColumns.missing_columns_for_block(block_info, DasCore.get_local_custody_columns())

    if Enum.empty?(missing_columns) do
      Logger.debug("[PendingBlocks] No missing data columns for block, process it", log_md)
      Blocks.new_block_info(block_info)
      process_block_and_check_children(store, block_info)
    else
      Logger.debug(
        "[PendingBlocks] Missing data columns for block, scheduling download",
        log_md
      )

      DataColumnDownloader.request_columns_by_root(
        missing_columns,
        &process_data_columns/2,
        @download_retries
      )

      block_info
      |> BlockInfo.change_status(:download_columns)
      |> Blocks.new_block_info()

      store
    end
  end

  @doc """
  Sends any blocks that are ready to block processing. This should usually be called only by this
  module after receiving a new block, but there are some other cases like at node startup, as there
  may be pending blocks from prior executions.
  """
  @spec process_blocks(Store.t()) :: Store.t()
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

  @doc """
  Process incoming blobs if the block can be processed does so immediately.
  """
  @spec process_blobs(Store.t(), {:ok, [Types.BlobSidecar.t()]}) :: {:ok, Store.t()}
  def process_blobs(store, {:ok, blobs}) do
    blobs
    |> Blobs.add_blobs()
    |> Enum.reduce(store, fn root, store ->
      with %BlockInfo{status: :download_blobs} = block_info <- Blocks.get_block_info(root),
           [] <- Blobs.missing_for_block(block_info) do
        block_info
        |> Blocks.change_status(:pending)
        |> then(&process_block_and_check_children(store, &1))

        {:ok, store}
      else
        _ -> {:ok, store}
      end
    end)
  end

  @spec process_blobs(Store.t(), {:error, any()}) :: {:ok, Store.t()}
  def process_blobs(store, {:error, reason}) do
    # We might want to declare a block invalid here.
    Logger.error("[PendingBlocks] Error downloading blobs: #{inspect(reason)}")
    {:ok, store}
  end

  @doc """
  Process incoming data column sidecars (Fulu). If the block now has all custody columns,
  move it to pending and process it.
  """
  @spec process_data_columns(Store.t(), {:ok, [Types.DataColumnSidecar.t()]}) :: {:ok, Store.t()}
  def process_data_columns(store, {:ok, sidecars}) do
    sidecars
    |> DataColumns.add_columns()
    |> Enum.reduce(store, fn root, store ->
      with %BlockInfo{status: :download_columns} = block_info <- Blocks.get_block_info(root),
           [] <-
             DataColumns.missing_columns_for_block(
               block_info,
               DasCore.get_local_custody_columns()
             ) do
        block_info
        |> Blocks.change_status(:pending)
        |> then(&process_block_and_check_children(store, &1))

        {:ok, store}
      else
        _ -> {:ok, store}
      end
    end)
  end

  @spec process_data_columns(Store.t(), {:error, :no_peers}) :: {:ok, Store.t()}
  def process_data_columns(store, {:error, :no_peers}) do
    Logger.warning("[PendingBlocks] No peers for data column download, scheduling retry")
    Process.send_after(self(), :retry_download_columns, 30_000)
    {:ok, store}
  end

  @spec process_data_columns(Store.t(), {:error, any()}) :: {:ok, Store.t()}
  def process_data_columns(store, {:error, reason}) do
    Logger.error("[PendingBlocks] Error downloading data columns: #{inspect(reason)}")
    {:ok, store}
  end

  @doc """
  Re-triggers data column downloads for all blocks stuck in :download_columns status.
  Called when peers become available after an earlier :no_peers failure.
  """
  @spec retry_download_columns(Store.t()) :: Store.t()
  def retry_download_columns(store) do
    case Blocks.get_blocks_with_status(:download_columns) do
      {:ok, blocks} ->
        custody_cols = DasCore.get_local_custody_columns()

        Enum.each(blocks, fn block_info ->
          missing = DataColumns.missing_columns_for_block(block_info, custody_cols)

          unless Enum.empty?(missing) do
            DataColumnDownloader.request_columns_by_root(
              missing,
              &process_data_columns/2,
              @download_retries
            )
          end
        end)

      {:error, reason} ->
        Logger.error("[PendingBlocks] Failed to get :download_columns blocks: #{reason}")
    end

    store
  end

  ##########################
  ### Private Functions
  ##########################

  # Processes a block. If it was transitioned or declared invalid, then process_blocks
  # is called to check if there's any children that can now be processed. This function
  # is only to be called when a new block is saved as pending, not when processing blocks
  # in batch, to avoid unneeded recursion.
  defp process_block_and_check_children(store, block_info) do
    case process_block(store, block_info) do
      {store, result} when result in [:transitioned, :invalid] -> process_blocks(store)
      {store, _other} -> store
    end
  end

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
            handle_on_block_error(store, block_info, reason, log_md)
        end

      _other ->
        {store, :ok}
    end
  end

  defp handle_on_block_error(store, block_info, reason, log_md) do
    if execution_layer_error?(reason) do
      # Transient EL error (connectivity, auth, etc.) — keep block as :pending.
      # process_blocks is only triggered by :transitioned/:invalid events, so we
      # schedule a delayed retry message to the calling GenServer (Libp2pPort).
      Logger.warning(
        "[PendingBlocks] Transient EL error, scheduling retry: #{reason}",
        log_md
      )

      Process.send_after(self(), :retry_pending_blocks, 10_000)
      {store, :ok}
    else
      Logger.error(
        "[PendingBlocks] Saving block as invalid after ForkChoice.on_block/2 error: #{reason}",
        log_md
      )

      Blocks.change_status(block_info, :invalid)
      {store, :invalid}
    end
  end

  # Errors from the execution layer (connectivity, auth, etc.) are transient and should not
  # permanently invalidate a block. Only errors from the EL explicitly rejecting the payload
  # (e.g. "Invalid execution payload") or from the state transition are permanent.
  defp execution_layer_error?(reason) do
    String.starts_with?(reason, "Error when calling execution client:")
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
