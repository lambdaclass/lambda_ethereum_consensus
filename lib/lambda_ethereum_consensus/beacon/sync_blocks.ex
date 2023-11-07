defmodule LambdaEthereumConsensus.Beacon.SyncBlocks do
  @moduledoc false

  use GenServer

  require Logger

  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.ForkChoice.Store
  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.StateTransition.Misc

  @blocks_per_chunk 20

  @type state :: %{
          chunks: [%{from: integer(), count: integer()}]
        }

  ##########################
  ### Public API
  ##########################

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init(any) :: {:ok, state()}
  def init(_opts) do
    schedule_sync()

    # TODO: this is a hack to make sure the on_tick has been called at least once
    Process.sleep(2000)

    {:ok, checkpoint} = Store.get_finalized_checkpoint()

    initial_slot = Misc.compute_start_slot_at_epoch(checkpoint.epoch)
    last_slot = Store.get_current_slot()

    Logger.info(
      "Syncing from slot #{initial_slot} to #{last_slot}, count: #{last_slot - initial_slot + 1}"
    )

    chunks =
      Enum.chunk_every(initial_slot..last_slot, @blocks_per_chunk)
      |> Enum.map(fn chunk ->
        first_slot = List.first(chunk)
        last_slot = List.last(chunk)
        count = last_slot - first_slot + 1
        %{from: first_slot, count: count}
      end)

    {:ok, %{chunks: chunks}}
  end

  @impl GenServer
  @spec handle_info(:sync, state()) :: {:noreply, state()}
  def handle_info(:sync, %{chunks: chunks}) do
    Logger.info("Syncing. Blocks remaining: #{Enum.count(chunks) * @blocks_per_chunk}")

    results =
      chunks
      |> Task.async_stream(
        fn chunk -> fetch_blocks_by_slot(chunk.from, chunk.count) end,
        max_concurrency: 20,
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

    if not Enum.empty?(remaining_chunks) do
      schedule_sync()
    end

    {:noreply,
     %{
       chunks: remaining_chunks
     }}
  end

  @spec fetch_blocks_by_slot(non_neg_integer(), integer()) ::
          {:ok, [SszTypes.SignedBeaconBlock]} | {:error, any()}
  def fetch_blocks_by_slot(from, count) do
    case BlockDownloader.request_blocks_by_slot(from, count, 0) do
      {:ok, blocks} ->
        {:ok, blocks}

      {:error, error} ->
        if not String.contains?(inspect(error), "failed to dial") do
          Logger.warning(
            "Blocks download failed for slot #{from} count #{count} Error: #{inspect(error)}"
          )
        end

        {:error, error}
    end
  end

  defp schedule_sync do
    Process.send_after(self(), :sync, 1_000)
  end
end
