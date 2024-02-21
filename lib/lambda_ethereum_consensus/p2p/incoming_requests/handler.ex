defmodule LambdaEthereumConsensus.P2P.IncomingRequests.Handler do
  @moduledoc """
  This module handles Req/Resp domain requests.
  """
  require Logger

  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.{Libp2pPort, P2P}
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks

  require Logger

  @spec handle(String.t(), String.t(), binary()) :: any()
  def handle(name, message_id, message) do
    case handle_req(name, message_id, message) do
      :ok -> :ok
      {:error, error} -> Logger.error("[#{name}] Request error: #{inspect(error)}")
    end
  end

  @spec handle_req(String.t(), String.t(), binary()) ::
          :ok | {:error, String.t()}
  defp handle_req(protocol_name, message_id, message)

  defp handle_req("status/1/ssz_snappy", message_id, message) do
    with {:ok, request} <- ReqResp.decode(message, Types.StatusMessage),
         Logger.debug("[Status] '#{inspect(request)}'"),
         {:ok, current_status} <- BeaconChain.get_current_status_message(),
         {:ok, payload} <- ReqResp.encode_ok(current_status) do
      Libp2pPort.send_response(message_id, payload)
    end
  end

  defp handle_req("goodbye/1/ssz_snappy", message_id, message) do
    with {:ok, goodbye_reason} <- ReqResp.decode(message, TypeAliases.uint64()),
         Logger.debug("[Goodbye] reason: #{goodbye_reason}"),
         {:ok, payload} <- ReqResp.encode_ok({0, TypeAliases.uint64()}) do
      Libp2pPort.send_response(message_id, payload)
    else
      # Ignore read errors, since some peers eagerly disconnect.
      {:error, "failed to read"} ->
        Logger.debug("[Goodbye] failed to read")
        :ok

      "" ->
        Logger.debug("[Goodbye] empty message")
        :ok

      err ->
        err
    end
  end

  defp handle_req("ping/1/ssz_snappy", message_id, message) do
    # Values are hardcoded
    with {:ok, seq_num} <- ReqResp.decode(message, TypeAliases.uint64()),
         Logger.debug("[Ping] seq_number: #{seq_num}"),
         seq_number = P2P.Metadata.get_seq_number(),
         {:ok, payload} <- ReqResp.encode_ok({seq_number, TypeAliases.uint64()}) do
      Libp2pPort.send_response(message_id, payload)
    end
  end

  defp handle_req("metadata/2/ssz_snappy", message_id, _message) do
    # NOTE: there's no request content so we just ignore it
    with {:ok, payload} <- P2P.Metadata.get_metadata() |> ReqResp.encode_ok() do
      Libp2pPort.send_response(message_id, payload)
    end
  end

  defp handle_req("beacon_blocks_by_range/2/ssz_snappy", message_id, message) do
    with {:ok, request} <- ReqResp.decode(message, Types.BeaconBlocksByRangeRequest) do
      %{start_slot: start_slot, count: count} = request

      Logger.info("[BlocksByRange] requested #{count} slots, starting from #{start_slot}")

      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      end_slot = start_slot + (truncated_count - 1)

      response_chunk =
        start_slot..end_slot
        |> Enum.map(&BlockDb.get_block_by_slot/1)
        |> Enum.map(&map_block_result/1)
        |> Enum.reject(&(&1 == :skip))
        |> ReqResp.encode_ok_chunks()

      Libp2pPort.send_response(message_id, response_chunk)
    end
  end

  defp handle_req("beacon_blocks_by_root/2/ssz_snappy", message_id, message) do
    with {:ok, %{body: body}} <- ReqResp.decode(message, Types.BeaconBlocksByRootRequest) do
      count = length(body)
      Logger.info("[BlocksByRoot] requested #{count} number of blocks")
      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      response_chunk =
        body
        |> Enum.take(truncated_count)
        |> Enum.map(&Blocks.get_signed_block/1)
        |> Enum.map(&map_block_result/1)
        |> Enum.reject(&(&1 == :skip))
        |> ReqResp.encode_ok_chunks()

      Libp2pPort.send_response(message_id, response_chunk)
    end
  end

  defp handle_req(protocol, _message_id, _message) do
    # This should never happen, since Libp2p only accepts registered protocols
    Logger.error("Unsupported protocol: #{protocol}")
    :ok
  end

  defp map_block_result({:ok, block}),
    do: {:ok, {block, BeaconChain.get_fork_digest_for_slot(block.message.slot)}}

  defp map_block_result({:error, _}), do: {:error, {2, "Server Error"}}
  defp map_block_result(:not_found), do: {:error, {3, "Resource Unavailable"}}
  defp map_block_result(:empty_slot), do: :skip
end
