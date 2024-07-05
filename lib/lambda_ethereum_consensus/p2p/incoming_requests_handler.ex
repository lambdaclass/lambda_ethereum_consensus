defmodule LambdaEthereumConsensus.P2P.IncomingRequestsHandler do
  @moduledoc """
  This module handles Req/Resp domain requests.
  """

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.P2P.Metadata
  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks

  require Logger

  @request_prefix "/eth2/beacon_chain/req/"
  @request_names [
    "status/1",
    "goodbye/1",
    "ping/1",
    "beacon_blocks_by_range/2",
    "beacon_blocks_by_root/2",
    "metadata/2"
  ]

  @spec protocol_ids() :: list(String.t())
  def protocol_ids() do
    @request_names |> Enum.map(&Enum.join([@request_prefix, &1, "/ssz_snappy"]))
  end

  @spec handle(String.t(), String.t(), binary()) :: {:ok, any()} | {:error, String.t()}
  def handle(@request_prefix <> name, message_id, message) do
    Logger.debug("'#{name}' request received")

    result =
      :telemetry.span([:port, :request], %{}, fn ->
        {handle_req(name, message_id, message), %{module: "handler", request: inspect(name)}}
      end)

    case result do
      {:error, error} -> {:error, "[#{name}] Request error: #{inspect(error)}"}
      result -> result
    end
  end

  @spec handle_req(String.t(), String.t(), binary()) ::
          :ok | {:ok, any()} | {:error, String.t()}
  defp handle_req(protocol_name, message_id, message)

  defp handle_req("status/1/ssz_snappy", message_id, message) do
    with {:ok, request} <- ReqResp.decode_request(message, Types.StatusMessage) do
      Logger.debug("[Status] '#{inspect(request)}'")
      payload = ForkChoice.get_current_status_message() |> ReqResp.encode_ok()
      {:ok, {message_id, payload}}
    end
  end

  defp handle_req("goodbye/1/ssz_snappy", _, "") do
    # ignore empty messages
    {:error, "Empty message"}
  end

  defp handle_req("goodbye/1/ssz_snappy", message_id, message) do
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

  defp handle_req("ping/1/ssz_snappy", message_id, message) do
    # Values are hardcoded
    with {:ok, seq_num} <- ReqResp.decode_request(message, TypeAliases.uint64()) do
      Logger.debug("[Ping] seq_number: #{seq_num}")
      seq_number = Metadata.get_seq_number()
      payload = ReqResp.encode_ok({seq_number, TypeAliases.uint64()})
      {:ok, {message_id, payload}}
    end
  end

  defp handle_req("metadata/2/ssz_snappy", message_id, _message) do
    # NOTE: there's no request content so we just ignore it
    payload = Metadata.get_metadata() |> ReqResp.encode_ok()
    {:ok, {message_id, payload}}
  end

  defp handle_req("beacon_blocks_by_range/2/ssz_snappy", message_id, message) do
    with {:ok, request} <- ReqResp.decode_request(message, Types.BeaconBlocksByRangeRequest) do
      %{start_slot: start_slot, count: count} = request

      Logger.info("[BlocksByRange] requested #{count} slots, starting from #{start_slot}")

      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      end_slot = start_slot + (truncated_count - 1)

      # TODO: extend cache to support slots as keys
      response_chunk =
        start_slot..end_slot
        |> Enum.map(&BlockDb.get_block_info_by_slot/1)
        |> Enum.map(&map_block_result/1)
        |> Enum.reject(&(&1 == :skip))
        |> ReqResp.encode_response()

      {:ok, {message_id, response_chunk}}
    end
  end

  defp handle_req("beacon_blocks_by_root/2/ssz_snappy", message_id, message) do
    with {:ok, roots} <-
           ReqResp.decode_request(message, TypeAliases.beacon_blocks_by_root_request()) do
      count = length(roots)
      Logger.info("[BlocksByRoot] requested #{count} number of blocks")
      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      response_chunk =
        roots
        |> Enum.take(truncated_count)
        |> Enum.map(&Blocks.get_block_info/1)
        |> Enum.map(&map_block_result/1)
        |> Enum.reject(&(&1 == :skip))
        |> ReqResp.encode_response()

      {:ok, {message_id, response_chunk}}
    end
  end

  defp handle_req(protocol, _message_id, _message) do
    # This should never happen, since Libp2p only accepts registered protocols
    {:error, "Unsupported protocol: #{protocol}"}
  end

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
