defmodule Mix.Tasks.Bench.Blocks do
  @moduledoc """
  Process downloaded blocks through the fork choice pipeline.

  Loads cached benchmark data from disk (produced by `mix bench.download`)
  and processes blocks sequentially through `ForkChoice.process_block/2`.

  ## Usage

      mix bench.blocks --data-dir bench/data/slot_9649056_200
      mix bench.blocks --data-dir bench/data/slot_9649056_200 --log-level warning
  """
  use Mix.Task

  require Logger

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.Store
  alias LambdaEthereumConsensus.Store.CheckpointStates
  alias LambdaEthereumConsensus.Store.DataColumnDb
  alias Types.BlockInfo
  alias Types.DataColumnSidecar
  alias Types.SignedBeaconBlock

  @shortdoc "Run block processing benchmark"

  @switches [data_dir: :string, log_level: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: @switches)

    data_dir =
      opts[:data_dir] || Mix.raise("--data-dir is required")

    log_level =
      opts
      |> Keyword.get(:log_level, "info")
      |> String.to_existing_atom()

    Logger.configure(level: log_level)

    data_dir = Path.expand(data_dir)

    unless File.dir?(data_dir) do
      Mix.raise("Data directory does not exist: #{data_dir}")
    end

    metadata = read_metadata(data_dir)
    start_slot = metadata["start_slot"]
    count = metadata["count"]

    # We skip app.start because runtime.exs parses System.argv()
    # with strict validation, rejecting our custom flags.
    # boot_infrastructure starts everything we need directly.

    network = metadata["network"] || "mainnet"
    boot_infrastructure(network)

    anchor_state = load_state(data_dir)
    anchor_block = load_anchor_block(data_dir, start_slot)
    blocks = load_blocks(data_dir, start_slot)
    column_count = load_all_columns(data_dir)

    Logger.info("Loaded anchor state at slot #{anchor_state.slot}")
    Logger.info("Loaded #{length(blocks)} blocks, #{column_count} data columns")

    {:ok, store} = Types.Store.get_forkchoice_store(anchor_state, anchor_block)
    store = Handlers.on_tick(store, :os.system_time(:second))

    {_store, results} = process_blocks(blocks, store)

    print_summary(results, start_slot, count)
  end

  defp read_metadata(data_dir) do
    path = Path.join(data_dir, "metadata.json")

    case File.read(path) do
      {:ok, contents} -> Jason.decode!(contents)
      {:error, reason} -> Mix.raise("Failed to read metadata.json: #{reason}")
    end
  end

  defp boot_infrastructure(network) do
    Application.ensure_all_started(:snappyer)
    Application.ensure_all_started(:jason)

    # Configure ChainSpec
    config = ConfigUtils.parse_config!(network)
    Application.put_env(:lambda_ethereum_consensus, ChainSpec, config: config)

    # Mock the engine API
    Application.put_env(
      :lambda_ethereum_consensus,
      LambdaEthereumConsensus.Execution.EngineApi,
      implementation: LambdaEthereumConsensus.Execution.EngineApi.Mocked
    )

    CheckpointStates.new()

    # Use a temporary directory for LevelDB
    tmp_db_dir =
      Path.join(System.tmp_dir!(), "bench_blocks_#{System.unique_integer([:positive])}")

    {:ok, _} = Store.Db.start_link(dir: tmp_db_dir)
    {:ok, _} = Store.Blocks.start_link([])
    {:ok, _} = Store.BlockStates.start_link([])
    Cache.initialize_cache()

    {:ok, _} = Task.Supervisor.start_link(name: StoreStatesSupervisor)
    {:ok, _} = Task.Supervisor.start_link(name: PruneStatesSupervisor)
    {:ok, _} = Task.Supervisor.start_link(name: PruneBlocksSupervisor)
    {:ok, _} = Task.Supervisor.start_link(name: PruneBlobsSupervisor)
  end

  defp load_state(data_dir) do
    decompress_and_decode(Path.join(data_dir, "state.ssz_snappy"), Types.BeaconState)
  end

  defp load_anchor_block(data_dir, start_slot) do
    decompress_and_decode(
      Path.join(data_dir, "block_#{start_slot}.ssz_snappy"),
      SignedBeaconBlock
    )
  end

  # Load all block files except the anchor block (which is at start_slot)
  defp load_blocks(data_dir, start_slot) do
    Path.wildcard(Path.join(data_dir, "block_*.ssz_snappy"))
    |> Enum.map(fn path ->
      slot = extract_slot_from_filename(path)
      {slot, path}
    end)
    |> Enum.reject(fn {slot, _} -> slot == start_slot end)
    |> Enum.sort_by(fn {slot, _} -> slot end)
    |> Enum.map(fn {slot, path} ->
      block = decompress_and_decode(path, SignedBeaconBlock)
      {slot, block}
    end)
  end

  defp load_all_columns(data_dir) do
    Path.wildcard(Path.join(data_dir, "columns_*"))
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(fn col_dir ->
      Path.wildcard(Path.join(col_dir, "column_*.ssz_snappy"))
      |> Enum.map(fn path ->
        column = decompress_and_decode(path, DataColumnSidecar)
        DataColumnDb.store_data_column(column)
        column
      end)
    end)
    |> length()
  end

  defp decompress_and_decode(path, type) do
    {:ok, compressed} = File.read(path)
    {:ok, ssz_data} = :snappyer.decompress(compressed)
    {:ok, object} = Ssz.from_ssz(ssz_data, type)
    object
  end

  defp extract_slot_from_filename(path) do
    path
    |> Path.basename()
    |> String.replace_prefix("block_", "")
    |> String.replace_suffix(".ssz_snappy", "")
    |> String.to_integer()
  end

  defp process_blocks(blocks, store) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")

    Enum.reduce(blocks, {store, []}, fn {slot, signed_block}, {store, results} ->
      block_info = BlockInfo.from_block(signed_block, :pending)

      start_time = System.monotonic_time(:millisecond)

      case ForkChoice.process_block(block_info, store) do
        {:ok, new_store, _timings} ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          epoch_boundary? = rem(slot, slots_per_epoch) == 0

          Logger.info(
            "Slot #{slot}: #{elapsed}ms#{if epoch_boundary?, do: " [epoch boundary]", else: ""}"
          )

          {new_store, [{slot, elapsed, epoch_boundary?} | results]}

        {:error, reason} ->
          elapsed = System.monotonic_time(:millisecond) - start_time
          Logger.error("Slot #{slot}: failed after #{elapsed}ms: #{inspect(reason)}")
          {store, results}
      end
    end)
    |> then(fn {store, results} -> {store, Enum.reverse(results)} end)
  end

  defp print_summary(results, start_slot, count) do
    total_blocks = length(results)
    empty_slots = count - total_blocks

    {epoch_results, non_epoch_results} =
      Enum.split_with(results, fn {_slot, _ms, epoch?} -> epoch? end)

    total_ms = results |> Enum.map(fn {_, ms, _} -> ms end) |> Enum.sum()

    avg_ms =
      if total_blocks > 0, do: Float.round(total_ms / total_blocks, 1), else: 0

    non_epoch_avg =
      case non_epoch_results do
        [] -> 0
        list -> Float.round(Enum.sum(Enum.map(list, fn {_, ms, _} -> ms end)) / length(list), 1)
      end

    IO.puts("\n=== Block Processing Benchmark ===")
    IO.puts("Slots:     #{start_slot} -> #{start_slot + count}")
    IO.puts("Blocks:    #{total_blocks} / #{count} (#{empty_slots} empty slots)")
    IO.puts("Epochs:    #{length(epoch_results)} boundaries crossed")
    IO.puts("")
    IO.puts("Total time:     #{format_time(total_ms)}")
    IO.puts("Avg per block:  #{round(avg_ms)}ms")

    if epoch_results != [] do
      epoch_details =
        epoch_results
        |> Enum.map(fn {slot, ms, _} -> "slot #{slot}: #{format_time(ms)}" end)
        |> Enum.join(", ")

      IO.puts("Epoch blocks:   [#{epoch_details}]")
    end

    IO.puts("Non-epoch avg:  #{round(non_epoch_avg)}ms")
  end

  defp format_time(ms) when ms >= 1000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_time(ms), do: "#{round(ms)}ms"
end
