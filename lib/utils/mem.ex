defmodule LambdaEthereumConsensus.Mem do
  @moduledoc """
  Memory introspection utilities for diagnosing BeaconState memory usage.

  Usage in IEx (via `make iex` or `make test-iex`):

      alias LambdaEthereumConsensus.Mem
      Mem.report()              # Full memory report
      Mem.ets_tables()          # All ETS tables ranked by memory
      Mem.top_processes(10)     # Top 10 processes by heap size
      Mem.state_cache_detail()  # Per-entry breakdown of BlockStates cache
      Mem.checkpoint_detail()   # Per-entry breakdown of CheckpointStates
      Mem.binary_stats()        # Binary/refc binary pressure
      Mem.cache_tables()        # StateTransition cache table sizes
  """

  @word_size :erlang.system_info(:wordsize)

  # Known ETS tables in this project
  @known_tables [
    :states_by_block_hash,
    :states_by_block_hash_ttl_data,
    :blocks_by_hash,
    :blocks_by_hash_ttl_data,
    :checkpoint_states,
    :total_active_balance,
    :beacon_proposer_index,
    :active_validator_count,
    :beacon_committee,
    :active_validator_indices,
    :sync_committee_indices
  ]

  # ── Full Report ──────────────────────────────────────────────────────

  @doc """
  Print a full memory report: BEAM totals, ETS breakdown, top processes, and cache details.
  """
  def report do
    IO.puts("\n=== BEAM Memory Summary ===\n")
    beam_summary()

    IO.puts("\n=== ETS Tables (Top 20 by Memory) ===\n")
    ets_tables(20)

    IO.puts("\n=== Top 10 Processes by Heap ===\n")
    top_processes(10)

    IO.puts("\n=== BlockStates Cache (#{table_entry_count(:states_by_block_hash)} entries) ===\n")
    state_cache_detail()

    IO.puts("\n=== CheckpointStates (#{table_entry_count(:checkpoint_states)} entries) ===\n")
    checkpoint_detail()

    IO.puts("\n=== StateTransition Caches ===\n")
    cache_tables()

    IO.puts("\n=== Binary / Refc Binary Stats ===\n")
    binary_stats()

    :ok
  end

  # ── BEAM Memory ──────────────────────────────────────────────────────

  @doc "Print BEAM memory breakdown from :erlang.memory/0."
  def beam_summary do
    mem = :erlang.memory()

    rows = [
      {"total", mem[:total]},
      {"processes", mem[:processes]},
      {"processes_used", mem[:processes_used]},
      {"ets", mem[:ets]},
      {"binary", mem[:binary]},
      {"code", mem[:code]},
      {"atom", mem[:atom]},
      {"system", mem[:system]}
    ]

    header = String.pad_trailing("Category", 20) <> String.pad_leading("Bytes", 16) <> String.pad_leading("Human", 12)
    IO.puts(header)
    IO.puts(String.duplicate("-", 48))

    Enum.each(rows, fn {label, bytes} ->
      IO.puts(
        String.pad_trailing(label, 20) <>
          String.pad_leading(Integer.to_string(bytes), 16) <>
          String.pad_leading(human(bytes), 12)
      )
    end)
  end

  # ── ETS Tables ───────────────────────────────────────────────────────

  @doc "List all ETS tables ranked by memory usage."
  def ets_tables(limit \\ 30) do
    tables =
      :ets.all()
      |> Enum.map(fn tab ->
        info = :ets.info(tab)

        if info do
          %{
            name: info[:name] || tab,
            id: tab,
            size: info[:size],
            memory_words: info[:memory],
            memory_bytes: info[:memory] * @word_size,
            type: info[:type],
            owner: info[:owner]
          }
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.memory_bytes, :desc)
      |> Enum.take(limit)

    header =
      String.pad_trailing("Table", 40) <>
        String.pad_leading("Entries", 10) <>
        String.pad_leading("Memory", 14) <>
        String.pad_leading("Type", 14)

    IO.puts(header)
    IO.puts(String.duplicate("-", 78))

    Enum.each(tables, fn t ->
      IO.puts(
        String.pad_trailing(inspect(t.name), 40) <>
          String.pad_leading(Integer.to_string(t.size), 10) <>
          String.pad_leading(human(t.memory_bytes), 14) <>
          String.pad_leading(Atom.to_string(t.type), 14)
      )
    end)
  end

  # ── Top Processes ────────────────────────────────────────────────────

  @doc "List top N processes by total memory (heap + stack + mailbox)."
  def top_processes(n \\ 10) do
    procs =
      Process.list()
      |> Enum.map(fn pid ->
        case Process.info(pid, [:memory, :heap_size, :stack_size, :message_queue_len, :registered_name, :current_function]) do
          nil ->
            nil

          info ->
            %{
              pid: pid,
              name: info[:registered_name] || info[:current_function] || pid,
              memory: info[:memory],
              heap_words: info[:heap_size],
              stack_words: info[:stack_size],
              mq_len: info[:message_queue_len]
            }
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.memory, :desc)
      |> Enum.take(n)

    header =
      String.pad_trailing("Process", 50) <>
        String.pad_leading("Memory", 12) <>
        String.pad_leading("Heap", 12) <>
        String.pad_leading("MQ Len", 10)

    IO.puts(header)
    IO.puts(String.duplicate("-", 84))

    Enum.each(procs, fn p ->
      IO.puts(
        String.pad_trailing(format_name(p.name), 50) <>
          String.pad_leading(human(p.memory), 12) <>
          String.pad_leading(human(p.heap_words * @word_size), 12) <>
          String.pad_leading(Integer.to_string(p.mq_len), 10)
      )
    end)
  end

  # ── BlockStates Cache Detail ─────────────────────────────────────────

  @doc """
  Inspect each entry in the BlockStates ETS cache.
  Shows per-entry: whether `encoded` is present, beacon_state field sizes, field_hashes count.
  """
  def state_cache_detail do
    case safe_ets_tab2list(:states_by_block_hash) do
      nil ->
        IO.puts("Table :states_by_block_hash not found (node not running?)")

      entries ->
        if entries == [] do
          IO.puts("(empty)")
        else
          header =
            String.pad_trailing("Root (hex prefix)", 20) <>
              String.pad_leading("Slot", 10) <>
              String.pad_leading("Encoded?", 10) <>
              String.pad_leading("Enc. Size", 12) <>
              String.pad_leading("Validators", 12) <>
              String.pad_leading("FieldHash#", 12) <>
              String.pad_leading("ETS Words", 12)

          IO.puts(header)
          IO.puts(String.duplicate("-", 88))

          Enum.each(entries, fn {root, state_info, _ttl} ->
            bs = state_info.beacon_state
            root_hex = Base.encode16(root, case: :lower) |> String.slice(0, 16)
            slot = bs.slot
            has_encoded = if state_info.encoded, do: "yes", else: "no"
            enc_size = if state_info.encoded, do: byte_size(state_info.encoded), else: 0
            val_count = if is_struct(bs.validators, Aja.Vector), do: Aja.Vector.size(bs.validators), else: length(bs.validators)
            fh_count = map_size(state_info.field_hashes)

            # Measure actual ETS memory for this entry
            ets_words = ets_entry_words(:states_by_block_hash, root)

            IO.puts(
              String.pad_trailing(root_hex <> "...", 20) <>
                String.pad_leading(Integer.to_string(slot), 10) <>
                String.pad_leading(has_encoded, 10) <>
                String.pad_leading(human(enc_size), 12) <>
                String.pad_leading(Integer.to_string(val_count), 12) <>
                String.pad_leading(Integer.to_string(fh_count), 12) <>
                String.pad_leading(human(ets_words * @word_size), 12)
            )
          end)
        end

        total_mem = :ets.info(:states_by_block_hash, :memory) * @word_size
        IO.puts("\nTotal table memory: #{human(total_mem)}")
    end
  end

  # ── CheckpointStates Detail ──────────────────────────────────────────

  @doc "Inspect the checkpoint_states ETS table: entries, total memory."
  def checkpoint_detail do
    case safe_ets_tab2list(:checkpoint_states) do
      nil ->
        IO.puts("Table :checkpoint_states not found (node not running?)")

      entries ->
        count = length(entries)
        total_mem = :ets.info(:checkpoint_states, :memory) * @word_size

        IO.puts("Entries: #{count}")
        IO.puts("Total memory: #{human(total_mem)}")

        if count > 0 do
          IO.puts("")

          header =
            String.pad_trailing("Epoch", 10) <>
              String.pad_leading("Slot", 10) <>
              String.pad_leading("Root (prefix)", 20)

          IO.puts(header)
          IO.puts(String.duplicate("-", 40))

          Enum.each(entries, fn {checkpoint, state} ->
            root_hex = Base.encode16(checkpoint.root, case: :lower) |> String.slice(0, 16)

            IO.puts(
              String.pad_trailing(Integer.to_string(checkpoint.epoch), 10) <>
                String.pad_leading(Integer.to_string(state.slot), 10) <>
                String.pad_leading(root_hex <> "...", 20)
            )
          end)
        end
    end
  end

  # ── StateTransition Caches ──────────────────────────────────────────

  @doc "Show sizes and memory of the 6 StateTransition cache ETS tables."
  def cache_tables do
    cache_names = [
      :total_active_balance,
      :beacon_proposer_index,
      :active_validator_count,
      :beacon_committee,
      :active_validator_indices,
      :sync_committee_indices
    ]

    header =
      String.pad_trailing("Cache Table", 30) <>
        String.pad_leading("Entries", 10) <>
        String.pad_leading("Memory", 14)

    IO.puts(header)
    IO.puts(String.duplicate("-", 54))

    total = Enum.reduce(cache_names, 0, fn name, acc ->
      case :ets.info(name) do
        :undefined ->
          IO.puts(String.pad_trailing(Atom.to_string(name), 30) <> "  (not created)")
          acc

        info ->
          mem = info[:memory] * @word_size

          IO.puts(
            String.pad_trailing(Atom.to_string(name), 30) <>
              String.pad_leading(Integer.to_string(info[:size]), 10) <>
              String.pad_leading(human(mem), 14)
          )

          acc + mem
      end
    end)

    IO.puts(String.duplicate("-", 54))
    IO.puts(String.pad_trailing("TOTAL", 30) <> String.pad_leading("", 10) <> String.pad_leading(human(total), 14))
  end

  # ── Binary Stats ─────────────────────────────────────────────────────

  @doc """
  Show binary/refc binary memory stats.
  Large binaries (>64 bytes) are reference-counted and shared between processes.
  Leaking binary references is a common BEAM memory issue.
  """
  def binary_stats do
    mem = :erlang.memory()
    binary_mem = mem[:binary]

    IO.puts("Binary memory (refc binaries): #{human(binary_mem)}")
    IO.puts("Total BEAM memory:             #{human(mem[:total])}")
    IO.puts("Binary as % of total:          #{Float.round(binary_mem / max(mem[:total], 1) * 100, 1)}%")
    IO.puts("")

    # Find top processes by binary memory
    IO.puts("Top 5 processes by binary references:")
    IO.puts("")

    procs =
      Process.list()
      |> Enum.map(fn pid ->
        case Process.info(pid, [:binary, :registered_name, :memory]) do
          nil ->
            nil

          info ->
            bins = info[:binary] || []
            bin_mem = bins |> Enum.map(fn {_ref, size, _refcount} -> size end) |> Enum.sum()

            %{
              pid: pid,
              name: info[:registered_name] || pid,
              memory: info[:memory],
              bin_count: length(bins),
              bin_mem: bin_mem
            }
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.bin_mem, :desc)
      |> Enum.take(5)

    header =
      String.pad_trailing("Process", 45) <>
        String.pad_leading("Bin Count", 12) <>
        String.pad_leading("Bin Memory", 14) <>
        String.pad_leading("Total Mem", 14)

    IO.puts(header)
    IO.puts(String.duplicate("-", 85))

    Enum.each(procs, fn p ->
      IO.puts(
        String.pad_trailing(format_name(p.name), 45) <>
          String.pad_leading(Integer.to_string(p.bin_count), 12) <>
          String.pad_leading(human(p.bin_mem), 14) <>
          String.pad_leading(human(p.memory), 14)
      )
    end)
  end

  # ── Libp2pPort / Store Introspection ─────────────────────────────────

  @doc """
  Inspect the Libp2pPort GenServer state size. This process holds the Store
  with `store.states` and `store.checkpoint_states` maps.

  WARNING: This calls :sys.get_state which briefly blocks the GenServer.
  Do NOT call during active sync.
  """
  def libp2p_port_state do
    pid = Process.whereis(LambdaEthereumConsensus.Libp2pPort)

    if pid do
      info = Process.info(pid, [:memory, :heap_size, :message_queue_len])
      IO.puts("Libp2pPort process memory: #{human(info[:memory])}")
      IO.puts("Heap: #{human(info[:heap_size] * @word_size)}")
      IO.puts("Message queue: #{info[:message_queue_len]}")
    else
      IO.puts("Libp2pPort not running")
    end
  end

  # ── ETS Memory Delta Tracking ────────────────────────────────────────

  @doc """
  Take a snapshot of all known ETS tables. Call this before an operation,
  then call `diff_snapshot/1` after to see what changed.

      snap = Mem.snapshot()
      # ... do some operation ...
      Mem.diff_snapshot(snap)
  """
  def snapshot do
    @known_tables
    |> Enum.map(fn name ->
      case :ets.info(name) do
        :undefined -> {name, %{size: 0, memory: 0}}
        info -> {name, %{size: info[:size], memory: info[:memory] * @word_size}}
      end
    end)
    |> Map.new()
  end

  @doc "Compare current ETS state against a previous snapshot."
  def diff_snapshot(prev) do
    current = snapshot()

    header =
      String.pad_trailing("Table", 35) <>
        String.pad_leading("Entries", 12) <>
        String.pad_leading("Memory", 14) <>
        String.pad_leading("Delta", 14)

    IO.puts(header)
    IO.puts(String.duplicate("-", 75))

    Enum.each(@known_tables, fn name ->
      p = Map.get(prev, name, %{size: 0, memory: 0})
      c = Map.get(current, name, %{size: 0, memory: 0})
      delta = c.memory - p.memory

      if delta != 0 do
        sign = if delta > 0, do: "+", else: ""

        IO.puts(
          String.pad_trailing(Atom.to_string(name), 35) <>
            String.pad_leading("#{p.size}→#{c.size}", 12) <>
            String.pad_leading(human(c.memory), 14) <>
            String.pad_leading("#{sign}#{human(delta)}", 14)
        )
      end
    end)
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp human(bytes) when bytes >= 1_073_741_824, do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  defp human(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp human(bytes) when bytes >= 1_024, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp human(bytes), do: "#{bytes} B"

  defp format_name(name) when is_atom(name), do: inspect(name)
  defp format_name({m, f, a}), do: "#{inspect(m)}.#{f}/#{a}"
  defp format_name(pid) when is_pid(pid), do: inspect(pid)
  defp format_name(other), do: inspect(other)

  defp safe_ets_tab2list(table) do
    case :ets.info(table) do
      :undefined -> nil
      _ -> :ets.tab2list(table)
    end
  end

  defp table_entry_count(table) do
    case :ets.info(table, :size) do
      :undefined -> "?"
      n -> n
    end
  end

  defp ets_entry_words(table, key) do
    # Estimate: total table memory / entry count (ETS doesn't expose per-entry sizes)
    total = :ets.info(table, :memory)
    size = :ets.info(table, :size)
    if size > 0, do: div(total, size), else: 0
  end
end
