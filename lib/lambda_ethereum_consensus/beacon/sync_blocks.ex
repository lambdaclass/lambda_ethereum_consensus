defmodule LambdaEthereumConsensus.Beacon.SyncBlocks do
  @moduledoc """
    Performs an optimistic block sync from the finalized checkpoint to the current slot.
  """

  use Task

  require Logger

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.P2P.Gossip
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.SignedBeaconBlock

  @blocks_per_chunk 16

  @type chunk :: %{from: Types.slot(), count: integer()}

  def start_link(opts) do
    Task.start_link(__MODULE__, :run, [opts])
  end

  def run(_opts) do
    # Initial sleep for faster app start
    Process.sleep(1000)
    checkpoint = BeaconChain.get_finalized_checkpoint()
    initial_slot = Misc.compute_start_slot_at_epoch(checkpoint.epoch) + 1
    last_slot = ForkChoice.get_current_chain_slot()

    # If we're around genesis, we consider ourselves synced
    if last_slot > 0 do
      Enum.chunk_every(initial_slot..last_slot, @blocks_per_chunk)
      |> Enum.map(fn chunk ->
        first_slot = List.first(chunk)
        last_slot = List.last(chunk)
        count = last_slot - first_slot + 1
        %{from: first_slot, count: count}
      end)
      |> perform_sync()
    else
      start_subscriptions()
    end
  end

  @spec perform_sync([chunk()]) :: :ok
  def perform_sync(chunks) do
    remaining = chunks |> Stream.map(fn %{count: c} -> c end) |> Enum.sum()
    Logger.info("[Optimistic Sync] Blocks remaining: #{remaining}")

    results =
      chunks
      |> Task.async_stream(
        fn chunk -> fetch_blocks_by_slot(chunk.from, chunk.count) end,
        max_concurrency: 4,
        timeout: 20_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:error, error} -> {:error, error}
        {:exit, :timeout} -> {:error, "timeout"}
      end)

    results
    |> Enum.filter(fn result -> match?({:ok, _}, result) end)
    |> Enum.map(fn {:ok, blocks} -> blocks end)
    |> List.flatten()
    |> Enum.each(&PendingBlocks.add_block/1)

    remaining_chunks =
      Enum.zip(chunks, results)
      |> Enum.filter(fn {_chunk, result} -> match?({:error, _}, result) end)
      |> Enum.map(fn {chunk, _} -> chunk end)

    if Enum.empty?(chunks) do
      Logger.info("[Optimistic Sync] Sync completed")
      start_subscriptions()
    else
      Process.sleep(1000)
      perform_sync(remaining_chunks)
    end
  end

  # TODO: handle subscription failures.
  defp start_subscriptions() do
    Gossip.BeaconBlock.subscribe_to_topic()
    Gossip.BlobSideCar.subscribe_to_topics()
    Gossip.OperationsCollector.subscribe_to_topics()
  end

  @spec fetch_blocks_by_slot(Types.slot(), non_neg_integer()) ::
          {:ok, [SignedBeaconBlock.t()]} | {:error, String.t()}
  def fetch_blocks_by_slot(from, count) do
    case BlockDownloader.request_blocks_by_range(from, count, 0) do
      {:ok, blocks} ->
        {:ok, blocks}

      {:error, error} ->
        if not String.contains?(inspect(error), "failed to dial") do
          Logger.debug(
            "Blocks download failed for slot #{from} count #{count} Error: #{inspect(error)}"
          )
        end

        {:error, error}
    end
  end
end
