defmodule LambdaEthereumConsensus.P2P.IncomingRequestsHandler do
  @moduledoc """
  This module handles Req/Resp domain requests.
  """

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.P2P.Metadata
  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.DataColumnDb

  require Logger

  @request_prefix "/eth2/beacon_chain/req/"

  # On Fulu, advertise status/2 (adds earliest_available_slot), metadata/3
  # (adds custody_group_count), and the two new data column req/resp protocols.
  @request_names [
                   "status/1",
                   "goodbye/1",
                   "ping/1",
                   "beacon_blocks_by_range/2",
                   "beacon_blocks_by_root/2",
                   "metadata/2"
                 ] ++
                   (if Application.compile_env!(:lambda_ethereum_consensus, :fork) == :fulu do
                      [
                        "status/2",
                        "metadata/3",
                        "data_column_sidecars_by_range/1",
                        "data_column_sidecars_by_root/1"
                      ]
                    else
                      []
                    end)

  @spec protocol_ids() :: list(String.t())
  def protocol_ids() do
    @request_names |> Enum.map(&Enum.join([@request_prefix, &1, "/ssz_snappy"]))
  end

  @spec handle(String.t(), String.t(), binary(), Types.Store.t() | nil) ::
          {:ok, any()} | {:error, String.t()}
  def handle(protocol, message_id, message, store \\ nil)

  def handle(@request_prefix <> name, message_id, message, store) do
    Logger.debug("'#{name}' request received")

    result =
      Metrics.handler_span("request_handler", name |> String.split("/") |> List.first(), fn ->
        handle_req(name, message_id, message, store)
      end)

    case result do
      {:error, error} -> {:error, "[#{name}] Request error: #{inspect(error)}"}
      result -> result
    end
  end

  @spec handle_req(String.t(), String.t(), binary(), Types.Store.t() | nil) ::
          {:ok, any()} | {:error, String.t()}
  defp handle_req(protocol_name, message_id, message, store)

  defp handle_req("status/1/ssz_snappy", message_id, message, store) do
    with {:ok, request} <- ReqResp.decode_request(message, Types.StatusMessage) do
      Logger.debug("[Status] '#{inspect(request)}'")

      payload =
        if store,
          do: ForkChoice.get_current_status_message(store),
          else: ForkChoice.get_current_status_message()

      {:ok, {message_id, ReqResp.encode_ok(payload)}}
    end
  end

  defp handle_req("status/2/ssz_snappy", message_id, message, store) do
    with {:ok, request} <- ReqResp.decode_request(message, Types.StatusMessageV2) do
      Logger.debug("[StatusV2] '#{inspect(request)}'")

      payload =
        if store,
          do: ForkChoice.get_current_status_message_v2(store),
          else: ForkChoice.get_current_status_message_v2()

      {:ok, {message_id, ReqResp.encode_ok(payload)}}
    end
  end

  defp handle_req("goodbye/1/ssz_snappy", _, "", _store) do
    # ignore empty messages
    {:error, "Empty message"}
  end

  defp handle_req("goodbye/1/ssz_snappy", message_id, message, _store) do
    case ReqResp.decode_request(message, TypeAliases.uint64()) do
      {:ok, goodbye_reason} ->
        Logger.debug("[Goodbye] reason: #{goodbye_reason}")
        payload = ReqResp.encode_ok({0, TypeAliases.uint64()})
        {:ok, {message_id, payload}}

      # Ignore read errors, since some peers eagerly disconnect.
      err ->
        err
    end
  end

  defp handle_req("ping/1/ssz_snappy", message_id, message, _store) do
    # Values are hardcoded
    with {:ok, seq_num} <- ReqResp.decode_request(message, TypeAliases.uint64()) do
      Logger.debug("[Ping] seq_number: #{seq_num}")
      seq_number = Metadata.get_seq_number()
      payload = ReqResp.encode_ok({seq_number, TypeAliases.uint64()})
      {:ok, {message_id, payload}}
    end
  end

  defp handle_req("metadata/2/ssz_snappy", message_id, _message, _store) do
    # NOTE: there's no request content so we just ignore it
    payload = Metadata.get_metadata() |> ReqResp.encode_ok()
    {:ok, {message_id, payload}}
  end

  defp handle_req("beacon_blocks_by_range/2/ssz_snappy", message_id, message, _store) do
    with {:ok, request} <- ReqResp.decode_request(message, Types.BeaconBlocksByRangeRequest) do
      %{start_slot: start_slot, count: count} = request

      Logger.info("[BlocksByRange] requested #{count} slots, starting from #{start_slot}")

      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      end_slot = start_slot + (truncated_count - 1)

      # Spawn a Task for LevelDB reads to avoid blocking Libp2pPort.
      # BlocksByRange requires slot-keyed lookups (no ETS cache), so we
      # run them off the main process. If the task takes too long, return
      # an empty response rather than stalling Libp2pPort.
      task =
        Task.async(fn ->
          start_slot..end_slot
          |> Enum.map(&BlockDb.get_block_info_by_slot/1)
          |> Enum.map(&map_block_result/1)
        end)

      response_chunk =
        case Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill) do
          {:ok, results} -> results
          nil -> []
        end
        |> Enum.reject(&(&1 == :skip))
        |> ReqResp.encode_response()

      {:ok, {message_id, response_chunk}}
    end
  end

  defp handle_req("beacon_blocks_by_root/2/ssz_snappy", message_id, message, _store) do
    with {:ok, roots} <-
           ReqResp.decode_request(message, TypeAliases.beacon_blocks_by_root_request()) do
      count = length(roots)
      Logger.info("[BlocksByRoot] requested #{count} number of blocks")
      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      # Cache-only block lookups to avoid blocking Libp2pPort on LevelDB reads.
      response_chunk =
        roots
        |> Enum.take(truncated_count)
        |> Enum.map(&Blocks.get_block_info_cached/1)
        |> Enum.map(fn
          nil -> :skip
          block_info -> map_block_result(block_info)
        end)
        |> Enum.reject(&(&1 == :skip))
        |> ReqResp.encode_response()

      {:ok, {message_id, response_chunk}}
    end
  end

  defp handle_req("metadata/3/ssz_snappy", message_id, _message, _store) do
    # MetadataV3 (Fulu): adds custody_group_count to the metadata response.
    payload = Metadata.get_metadata() |> ReqResp.encode_ok()
    {:ok, {message_id, payload}}
  end

  defp handle_req("data_column_sidecars_by_root/1/ssz_snappy", message_id, message, _store) do
    with {:ok, identifiers} <-
           ReqResp.decode_request(message, TypeAliases.data_column_sidecars_by_root_request()) do
      # Each DataColumnsByRootIdentifier has block_root + columns (list of indices).
      # Flatten into individual (root, column_index) pairs and apply the total cap.
      max_columns = ChainSpec.get("MAX_REQUEST_DATA_COLUMN_SIDECARS")

      pairs =
        identifiers
        |> Enum.flat_map(fn %{block_root: root, columns: cols} ->
          Enum.map(cols, &{root, &1})
        end)
        |> Enum.take(max_columns)

      Logger.info("[DataColumnsByRoot] requested #{length(pairs)} columns")

      response_chunk =
        pairs
        |> Enum.map(fn {root, column_index} ->
          DataColumnDb.get_data_column_sidecar(root, column_index)
        end)
        |> Enum.map(&map_column_result/1)
        |> Enum.reject(&(&1 == :skip))
        |> ReqResp.encode_response()

      {:ok, {message_id, response_chunk}}
    end
  end

  defp handle_req("data_column_sidecars_by_range/1/ssz_snappy", message_id, _message, _store) do
    # DataColumnSidecarsByRangeRequest has: start_slot, count, columns.
    # We serve stored sidecars for the requested slot range and column indices.
    # TODO: implement full range serving once DataColumnDb supports slot-indexed iteration.
    Logger.info("[DataColumnsByRange] received request (not yet fully implemented)")
    {:ok, {message_id, ReqResp.encode_response([])}}
  end

  defp handle_req(protocol, _message_id, _message, _store) do
    # This should never happen, since Libp2p only accepts registered protocols
    {:error, "Unsupported protocol: #{protocol}"}
  end

  defp map_column_result({:ok, column}),
    do:
      {:ok,
       {column, ForkChoice.get_fork_digest_for_slot(column.signed_block_header.message.slot)}}

  defp map_column_result(:not_found), do: {:error, {3, "Resource Unavailable"}}
  defp map_column_result({:error, _}), do: {:error, {2, "Server Error"}}

  defp map_block_result(:not_found), do: map_block_result(nil)
  defp map_block_result(nil), do: {:error, {3, "Resource Unavailable"}}
  defp map_block_result(:empty_slot), do: :skip
  defp map_block_result({:ok, block}), do: map_block_result(block)
  defp map_block_result({:error, _}), do: {:error, {2, "Server Error"}}

  alias Types.BlockInfo

  defp map_block_result(%BlockInfo{} = block_info),
    do:
      {:ok,
       {block_info.signed_block,
        ForkChoice.get_fork_digest_for_slot(block_info.signed_block.message.slot)}}
end
