defmodule Mix.Tasks.Bench.Download do
  @moduledoc """
  Download blocks and state from a Beacon API node for benchmarking.

  Downloads a BeaconState at the start slot, then fetches blocks and blob sidecars
  for `count` consecutive slots. Blobs are converted to data column sidecars.
  Everything is saved to disk as SSZ snappy-compressed files.

  ## Usage

      mix bench.download --url http://localhost:5052 --start-slot 1000 --count 32

  ## Options

    * `--url` (required) - Beacon API base URL
    * `--start-slot` (required) - Slot to anchor from
    * `--count` (required) - Number of slots after start to fetch
    * `--data-dir` (optional, default `bench/data`) - Base directory for output
    * `--network` (optional, default `mainnet`) - Network config (mainnet, sepolia, etc.)

  ## Output Structure

      bench/data/slot_<start>_<count>/
        metadata.json
        state.ssz_snappy
        block_<slot>.ssz_snappy
        columns_<slot>/
          column_<index>.ssz_snappy
  """

  use Mix.Task

  @shortdoc "Download blocks from Beacon API for benchmarking"

  alias LambdaEthereumConsensus.StateTransition.DasCore
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

  @impl Mix.Task
  def run(args) do
    {url, start_slot, count, out_dir} = parse_and_setup(args)

    fetch_anchor_data!(url, start_slot, out_dir)

    results = fetch_block_range(url, start_slot, count, out_dir)

    Mix.shell().info("""

    Download complete!
      Directory: #{out_dir}
      Blocks found: #{results.blocks}
      Empty slots: #{results.empty}
      Total blobs: #{results.blobs}
      Total columns generated: #{results.columns}
    """)
  end

  defp parse_and_setup(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          url: :string,
          start_slot: :integer,
          count: :integer,
          data_dir: :string,
          network: :string
        ]
      )

    url = opts[:url] || Mix.raise("--url is required")
    start_slot = opts[:start_slot] || Mix.raise("--start-slot is required")
    count = opts[:count] || Mix.raise("--count is required")
    data_dir = opts[:data_dir] || "bench/data"
    network = opts[:network] || "mainnet"

    for app <- [:jason, :hackney, :tesla, :snappyer], do: Application.ensure_all_started(app)

    config = ConfigUtils.parse_config!(network)
    Application.put_env(:lambda_ethereum_consensus, ChainSpec, config: config)
    Code.ensure_loaded!(Ssz)
    Code.ensure_loaded!(Kzg)

    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")

    if rem(start_slot, slots_per_epoch) != 0 do
      Mix.shell().info(
        "WARNING: start-slot #{start_slot} is not an epoch boundary (SLOTS_PER_EPOCH=#{slots_per_epoch})"
      )
    end

    out_dir = Path.join(data_dir, "slot_#{start_slot}_#{count}")
    File.mkdir_p!(out_dir)

    metadata = %{
      url: url,
      start_slot: start_slot,
      count: count,
      network: network,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.write!(Path.join(out_dir, "metadata.json"), Jason.encode!(metadata, pretty: true))

    {url, start_slot, count, out_dir}
  end

  defp fetch_anchor_data!(url, start_slot, out_dir) do
    Mix.shell().info("Fetching state at slot #{start_slot}...")

    case get_ssz_from_url(url, "/eth/v2/debug/beacon/states/#{start_slot}", BeaconState) do
      {:ok, state} ->
        write_ssz_snappy!(Path.join(out_dir, "state.ssz_snappy"), state)
        Mix.shell().info("State saved.")

      {:error, reason} ->
        Mix.raise("Failed to fetch state: #{inspect(reason)}")
    end

    Mix.shell().info("Fetching anchor block at slot #{start_slot}...")

    case get_ssz_from_url(url, "/eth/v2/beacon/blocks/#{start_slot}", SignedBeaconBlock) do
      {:ok, anchor_block} ->
        write_ssz_snappy!(Path.join(out_dir, "block_#{start_slot}.ssz_snappy"), anchor_block)
        Mix.shell().info("Anchor block saved.")

      {:error, reason} ->
        Mix.raise("Failed to fetch anchor block: #{inspect(reason)}")
    end
  end

  defp fetch_block_range(url, start_slot, count, out_dir) do
    slots = (start_slot + 1)..(start_slot + count)

    Enum.reduce(slots, %{blocks: 0, empty: 0, blobs: 0, columns: 0}, fn slot, acc ->
      Mix.shell().info("Fetching slot #{slot}...")

      case get_ssz_from_url(url, "/eth/v2/beacon/blocks/#{slot}", SignedBeaconBlock) do
        {:ok, signed_block} ->
          write_ssz_snappy!(Path.join(out_dir, "block_#{slot}.ssz_snappy"), signed_block)
          acc = %{acc | blocks: acc.blocks + 1}
          fetch_and_convert_blobs(url, slot, signed_block, out_dir, acc)

        {:error, _} ->
          Mix.shell().info("  Slot #{slot}: empty (no block)")
          %{acc | empty: acc.empty + 1}
      end
    end)
  end

  defp fetch_and_convert_blobs(url, slot, signed_block, out_dir, acc) do
    case get_json(url, "/eth/v1/beacon/blob_sidecars/#{slot}") do
      {:ok, %{"data" => blob_data}} when blob_data != [] ->
        blobs =
          Enum.map(blob_data, fn sidecar ->
            sidecar["blob"]
            |> String.trim_leading("0x")
            |> Base.decode16!(case: :mixed)
          end)

        blob_count = length(blobs)
        Mix.shell().info("  Slot #{slot}: #{blob_count} blob(s), computing columns...")

        cells_and_proofs =
          Enum.map(blobs, fn blob ->
            {:ok, {cells, proofs}} = Kzg.compute_cells_and_kzg_proofs(blob)
            {cells, proofs}
          end)

        {:ok, columns} = DasCore.get_data_column_sidecars(signed_block, cells_and_proofs)

        # Write columns to disk
        col_dir = Path.join(out_dir, "columns_#{slot}")
        File.mkdir_p!(col_dir)

        Enum.each(columns, fn col ->
          write_ssz_snappy!(Path.join(col_dir, "column_#{col.index}.ssz_snappy"), col)
        end)

        column_count = length(columns)
        Mix.shell().info("  Slot #{slot}: wrote #{column_count} columns")
        %{acc | blobs: acc.blobs + blob_count, columns: acc.columns + column_count}

      {:ok, _} ->
        Mix.shell().info("  Slot #{slot}: no blobs")
        acc

      {:error, reason} ->
        Mix.shell().info("  Slot #{slot}: failed to fetch blobs: #{inspect(reason)}")
        acc
    end
  end

  defp get_ssz_from_url(base_url, path, result_type) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/octet-stream"}]}
      ])

    full_url = concat_url(base_url, path)

    case Tesla.get(client, full_url) do
      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} when status >= 400 ->
        {:error, {:http_error, status}}

      {:ok, response} ->
        Ssz.from_ssz(response.body, result_type)

      {:error, _} = err ->
        err
    end
  end

  defp get_json(base_url, path) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/json"}]},
        Tesla.Middleware.JSON
      ])

    full_url = concat_url(base_url, path)

    case Tesla.get(client, full_url) do
      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} when status >= 400 ->
        {:error, {:http_error, status}}

      {:ok, response} ->
        {:ok, response.body}

      {:error, _} = err ->
        err
    end
  end

  defp write_ssz_snappy!(path, object) do
    {:ok, ssz_data} = Ssz.to_ssz(object)
    {:ok, compressed} = :snappyer.compress(ssz_data)
    File.write!(path, compressed)
  end

  defp concat_url(base_url, path) do
    base_url
    |> URI.parse()
    |> URI.append_path(path)
    |> URI.to_string()
  end
end
