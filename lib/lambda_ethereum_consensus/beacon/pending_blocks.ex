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
  alias LambdaEthereumConsensus.Store.DataColumnDb
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
  # Max blocks to process per retry_download_columns invocation.
  # Keeps memory bounded by yielding the GenServer between batches,
  # allowing GC to reclaim BeaconState objects (~300MB each).
  @retry_batch_size 5
  # Max blocks to process per process_blocks invocation.
  # Yielding the GenServer between batches allows load shedding and
  # GC to run, preventing unbounded message queue growth during catch-up.
  @process_batch_size 5
  # Max retries for "parent state not found" errors before marking invalid.
  # Each retry is delayed by 5 seconds. This gives the async LevelDB write
  # time to complete (~15 seconds total) while preventing infinite spin loops
  # when the state is truly lost (e.g., processed during catch-up mode).
  @max_state_retries 3

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

    # If the block is new, was to be downloaded, or was previously marked invalid
    # (e.g. due to transient data availability failures), we (re-)process it.
    if is_nil(loaded_block) or loaded_block.status in [:download, :invalid] do
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

      # Ensure the retry heartbeat is running so partial/empty responses
      # or transient errors don't leave this block permanently stuck.
      Process.send_after(self(), :retry_download_columns, 12_000)

      block_info
      |> BlockInfo.change_status(:download_columns)
      |> Blocks.new_block_info()

      store
    end
  end

  @doc """
  On startup, resets blocks that were marked :invalid due to transient failures
  (e.g. data not available during catch-up sync). Blocks with signed_block data
  are moved back to :download_columns (Fulu) so they can be re-evaluated.
  Blocks without signed_block data (download markers) remain :invalid.
  """
  @spec recover_invalid_blocks() :: :ok | :recovered
  def recover_invalid_blocks() do
    case Blocks.get_blocks_with_status(:invalid) do
      {:ok, blocks} ->
        blocks
        |> Enum.filter(fn %BlockInfo{signed_block: sb} -> not is_nil(sb) end)
        |> recover_blocks()

      {:error, reason} ->
        Logger.warning("[PendingBlocks] Failed to get invalid blocks for recovery: #{reason}")
        :ok
    end
  end

  defp recover_blocks([]), do: :ok

  defp recover_blocks(recoverable) do
    Logger.info(
      "[PendingBlocks] Recovering #{length(recoverable)} previously-invalid blocks on startup"
    )

    target_status =
      if HardForkAliasInjection.fulu?(), do: :download_columns, else: :download_blobs

    Enum.each(recoverable, &Blocks.change_status(&1, target_status))
    :recovered
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
        sorted =
          Enum.sort_by(blocks, fn %BlockInfo{} = block_info ->
            block_info.signed_block.message.slot
          end)

        # Process blocks in small batches, yielding the GenServer between
        # batches so load shedding, GC, and other handlers can run.
        # Without batching, processing 60+ blocks in one callback kept
        # the GenServer busy for 3-5 minutes, causing mailbox overflow.
        {batch, rest} = Enum.split(sorted, @process_batch_size)

        store =
          Enum.reduce(batch, store, fn block_info, store ->
            {store, _state} = process_block(store, block_info)
            store
          end)

        if rest != [] do
          Process.send_after(self(), :retry_pending_blocks, 100)
        end

        store

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
    new_store =
      blobs
      |> Blobs.add_blobs()
      |> Enum.reduce(store, fn root, store ->
        with %BlockInfo{status: :download_blobs} = block_info <- Blocks.get_block_info(root),
             [] <- Blobs.missing_for_block(block_info) do
          block_info
          |> Blocks.change_status(:pending)
          |> then(&process_block_and_check_children(store, &1))
        else
          _ -> store
        end
      end)

    {:ok, new_store}
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
    custody_cols = DasCore.get_local_custody_columns()

    new_store =
      sidecars
      |> DataColumns.add_columns()
      |> Enum.reduce(store, fn root, store ->
        with %BlockInfo{status: :download_columns} = block_info <- Blocks.get_block_info(root),
             [] <-
               DataColumns.missing_columns_for_block(block_info, custody_cols) do
          block_info
          |> Blocks.change_status(:pending)
          |> then(&process_block_and_check_children(store, &1))
        else
          # Partial response: some columns received but others still missing.
          # Immediately re-request the remaining columns instead of waiting
          # 30-60s for the retry timer. This is the most common case on mainnet
          # where a peer custodies some but not all of our required columns.
          still_missing when is_list(still_missing) and still_missing != [] ->
            Logger.debug(
              "[PendingBlocks] Partial column response, #{length(still_missing)} still missing. Re-requesting immediately."
            )

            request_missing_columns(Blocks.get_block_info(root), custody_cols)
            store

          _ ->
            store
        end
      end)

    {:ok, new_store}
  end

  @spec process_data_columns(Store.t(), {:error, :no_peers}) :: {:ok, Store.t()}
  def process_data_columns(store, {:error, :no_peers}) do
    Logger.warning("[PendingBlocks] No peers for data column download, scheduling retry")
    Process.send_after(self(), :retry_download_columns, 5_000)
    {:ok, store}
  end

  @spec process_data_columns(Store.t(), {:error, any()}) :: {:ok, Store.t()}
  def process_data_columns(store, {:error, reason}) do
    Logger.error("[PendingBlocks] Error downloading data columns: #{inspect(reason)}")
    Process.send_after(self(), :retry_download_columns, 5_000)
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

        {ready, need_download} =
          Enum.split_with(blocks, fn block_info ->
            DataColumns.missing_columns_for_block(block_info, custody_cols) == []
          end)

        # Process only a small batch to prevent OOM from accumulating
        # BeaconStates (~300MB each) in memory. Yielding the GenServer
        # between batches allows GC and prevents message queue buildup.
        {batch, rest} = Enum.split(ready, @retry_batch_size)

        if batch != [] do
          Logger.info(
            "[PendingBlocks] Processing #{length(batch)} of #{length(ready)} ready blocks" <>
              " (#{length(need_download)} still downloading)"
          )
        end

        store =
          Enum.reduce(batch, store, fn block_info, acc ->
            block_info
            |> Blocks.change_status(:pending)
            |> then(&process_block_and_check_children(acc, &1))
          end)

        # Schedule a quick follow-up for remaining ready blocks.
        if rest != [] do
          Process.send_after(self(), :retry_download_columns, 1_000)
        end

        # Blocks still missing columns: re-request downloads.
        Enum.each(need_download, &request_missing_columns(&1, custody_cols))
        store

      {:error, reason} ->
        Logger.error("[PendingBlocks] Failed to get :download_columns blocks: #{reason}")
        store
    end
  end

  defp request_missing_columns(block_info, custody_cols) do
    missing = DataColumns.missing_columns_for_block(block_info, custody_cols)

    unless Enum.empty?(missing) do
      DataColumnDownloader.request_columns_by_root(
        missing,
        &process_data_columns/2,
        @download_retries
      )
    end
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
        process_transitioned_parent(store, block_info, message, log_md)

      _other ->
        {store, :ok}
    end
  end

  defp process_transitioned_parent(store, block_info, message, log_md) do
    # Skip blocks that are far behind the current head. During catch-up,
    # sync batches download blocks that may already be superseded by the
    # canonical chain. Processing them triggers expensive epoch processing
    # (10+ minutes for rewards_and_penalties + committee computation with
    # 2.2M validators) while blocking the Libp2pPort GenServer, causing
    # massive message queue buildup (50K-100K+).
    if message.slot + 2 < store.head_slot do
      Logger.info(
        "[PendingBlocks] Skipping block behind head (slot #{message.slot} vs head #{store.head_slot})",
        log_md
      )

      Blocks.change_status(block_info, :transitioned)
      {store, :transitioned}
    else
      case ForkChoice.on_block(store, block_info) do
        {:ok, store} ->
          Logger.debug(
            "[PendingBlocks] Block transitioned after ForkChoice.on_block/2",
            log_md
          )

          Blocks.change_status(block_info, :transitioned)
          {store, :transitioned}

        {:error, reason, store} ->
          handle_on_block_error(store, block_info, reason, log_md)
      end
    end
  end

  defp handle_on_block_error(store, block_info, reason, log_md) do
    cond do
      execution_layer_error?(reason) ->
        # Transient EL error (connectivity, auth, etc.) — keep block as :pending.
        # process_blocks is only triggered by :transitioned/:invalid events, so we
        # schedule a delayed retry message to the calling GenServer (Libp2pPort).
        Logger.warning(
          "[PendingBlocks] Transient EL error, scheduling retry: #{reason}",
          log_md
        )

        Process.send_after(self(), :retry_pending_blocks, 10_000)
        {store, :ok}

      data_availability_error?(reason) ->
        # Check whether columns are genuinely missing (transient — retry download)
        # or all present but verification failed (likely corrupted download).
        custody_cols = DasCore.get_local_custody_columns()
        missing = DataColumns.missing_columns_for_block(block_info, custody_cols)

        if missing != [] do
          Logger.warning(
            "[PendingBlocks] Data not available (#{length(missing)} columns missing)," <>
              " moving back to download_columns for retry",
            log_md
          )
        else
          # All columns present but KZG verification failed — purge stored columns
          # so they get re-downloaded fresh. Without this, retry_download_columns
          # would see "no missing columns", move the block to :pending, and loop.
          Logger.warning(
            "[PendingBlocks] Data not available but all #{length(custody_cols)} custody" <>
              " columns present — purging columns for re-download",
            log_md
          )

          DataColumnDb.delete_columns_for_block(block_info.root, custody_cols)
        end

        Blocks.change_status(block_info, :download_columns)
        request_missing_columns(block_info, custody_cols)
        Process.send_after(self(), :retry_download_columns, 5_000)
        {store, :ok}

      timing_error?(reason) ->
        # "block is from the future" happens after GenServer restart when the
        # store's time hasn't caught up via on_tick yet. Keep block as :pending
        # and retry after a delay — the time will advance and the block will pass.
        Logger.warning(
          "[PendingBlocks] Transient timing error, scheduling retry: #{reason}",
          log_md
        )

        Process.send_after(self(), :retry_pending_blocks, 12_000)
        {store, :ok}

      parent_state_missing_error?(reason) ->
        # Parent state not found can be transient: the async LevelDB write may
        # not have completed yet, or the state was evicted from the 16-entry ETS
        # cache during expensive checkpoint state computation (epoch boundaries).
        # Retry a few times to let the async write complete, but give up after
        # @max_state_retries to avoid spinning forever when the state is truly lost
        # (e.g., processed during catch-up mode where ETS/LevelDB writes are skipped).
        retry_key = {:state_retry, block_info.root}
        retries = Process.get(retry_key, 0)

        if retries < @max_state_retries do
          Process.put(retry_key, retries + 1)

          Logger.warning(
            "[PendingBlocks] Parent state not found (attempt #{retries + 1}/#{@max_state_retries}), scheduling retry: #{reason}",
            log_md
          )

          Process.send_after(self(), :retry_pending_blocks, 5_000)
          {store, :ok}
        else
          Process.delete(retry_key)

          Logger.error(
            "[PendingBlocks] Parent state permanently unavailable after #{@max_state_retries} retries, marking invalid: #{reason}",
            log_md
          )

          Blocks.change_status(block_info, :invalid)
          {store, :invalid}
        end

      true ->
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

  # Data availability failures are transient during catch-up sync — custody columns
  # may not have been downloaded yet. The block should be retried, not invalidated.
  defp data_availability_error?(reason) do
    reason == "data not available"
  end

  # Timing errors happen after GenServer restart when the store's time hasn't
  # been advanced by on_tick yet. The block is valid but appears to be "from
  # the future" relative to the stale store time.
  defp timing_error?(reason) do
    reason == "block is from the future"
  end

  # Parent state missing errors are transient: they occur when the ETS LRU
  # cache (16 entries) evicts the parent state during expensive checkpoint
  # state computation, and the async LevelDB write hasn't completed yet.
  # After a short delay, the LevelDB write should finish and the state
  # becomes retrievable.
  defp parent_state_missing_error?(reason) do
    String.contains?(reason, "not found in store")
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
