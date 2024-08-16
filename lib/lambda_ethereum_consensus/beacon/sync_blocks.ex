defmodule LambdaEthereumConsensus.Beacon.SyncBlocks do
  @moduledoc """
    Performs an optimistic block sync from the finalized checkpoint to the current slot.
  """

  require Logger

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.BlockDownloader

  @blocks_per_chunk 16
  @retries 50

  @doc """
  Calculates how which blocks need to be downloaded to be up to date., and launches the download
  requests. Returns the amount of blocks that need to be downloaded.

  If N blocks should be downloaded, N/16 range requests are performed. When each of those
  finish, each block of those responses will be sent to libp2p port module individually using
  Libp2pPort.add_block/1.
  """
  @spec run() :: non_neg_integer()
  def run() do
    %{head_slot: head_slot} = ForkChoice.get_current_status_message()
    initial_slot = head_slot + 1
    last_slot = ForkChoice.get_current_chain_slot()

    # If we're around genesis, we consider ourselves synced
    if last_slot <= 0 do
      Logger.info("[Optimistic sync] At genesis. No block sync will be needed.")
      0
    else
      Logger.info(
        "[Optimistic sync] Performing optimistic sync between slots #{initial_slot} and #{last_slot}, for a total of #{last_slot - initial_slot + 1} slots."
      )

      initial_slot..last_slot
      |> Enum.chunk_every(@blocks_per_chunk)
      |> Enum.map(fn chunk ->
        first_slot = List.first(chunk)
        last_slot = List.last(chunk)
        count = last_slot - first_slot + 1

        Logger.info(
          "[Optimistic sync] Sending request for slots #{first_slot} to #{last_slot} (request size = #{count})."
        )

        BlockDownloader.request_blocks_by_range(
          first_slot,
          count,
          &on_chunk_downloaded/2,
          @retries
        )

        count
      end)
      |> Enum.sum()
    end
  end

  defp on_chunk_downloaded(store, {:ok, range, blocks}) do
    Libp2pPort.notify_blocks_downloaded(range, blocks)
    {:ok, store}
  end

  defp on_chunk_downloaded(store, {:error, range, reason}) do
    Libp2pPort.notify_block_download_failed(range, reason)
    {:ok, store}
  end
end
