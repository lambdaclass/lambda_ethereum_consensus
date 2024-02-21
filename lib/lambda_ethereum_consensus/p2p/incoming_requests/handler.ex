defmodule LambdaEthereumConsensus.P2P.IncomingRequests.Handler do
  @moduledoc """
  This module handles Req/Resp domain requests.
  """
  require Logger

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.{Libp2pPort, P2P}
  alias LambdaEthereumConsensus.SszEx
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
    with {:ok, request} <- decode_request(message, Types.StatusMessage, 84),
         Logger.debug("[Status] '#{inspect(request)}'"),
         {:ok, current_status} <- BeaconChain.get_current_status_message(),
         {:ok, payload} <- encode_response(current_status) do
      Libp2pPort.send_response(message_id, payload)
    end
  end

  defp handle_req("goodbye/1/ssz_snappy", message_id, message) do
    with {:ok, goodbye_reason} <- decode_request(message, TypeAliases.uint64(), 8),
         Logger.debug("[Goodbye] reason: #{goodbye_reason}"),
         {:ok, payload} <- encode_response({0, TypeAliases.uint64()}) do
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
    with {:ok, seq_num} <- decode_request(message, TypeAliases.uint64(), 8),
         Logger.debug("[Ping] seq_number: #{seq_num}"),
         {:ok, payload} <- encode_response({P2P.Metadata.get_seq_number(), TypeAliases.uint64()}) do
      Libp2pPort.send_response(message_id, payload)
    end
  end

  defp handle_req("metadata/2/ssz_snappy", message_id, _message) do
    # NOTE: there's no request content so we just ignore it
    with {:ok, payload} <- P2P.Metadata.get_metadata() |> encode_response() do
      Libp2pPort.send_response(message_id, payload)
    end
  end

  defp handle_req("beacon_blocks_by_range/2/ssz_snappy", message_id, message) do
    with {:ok, request} <- decode_request(message, Types.BeaconBlocksByRangeRequest, 24) do
      %{start_slot: start_slot, count: count} = request

      "[Received BlocksByRange Request] requested slots #{start_slot} to #{start_slot + count - 1}"
      |> Logger.info()

      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      end_slot = start_slot + (truncated_count - 1)

      response_chunk =
        start_slot..end_slot
        |> Enum.map(&BlockDb.get_block_by_slot/1)
        |> Enum.map_join(&create_block_response_chunk/1)

      Libp2pPort.send_response(message_id, response_chunk)
    end
  end

  defp handle_req("beacon_blocks_by_root/2/ssz_snappy", message_id, message) do
    with {:ok, %{body: body}} <- decode_request(message, Types.BeaconBlocksByRootRequest, 24) do
      count = length(body)
      Logger.info("[Received BlocksByRoot Request] requested #{count} number of blocks")
      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      response_chunk =
        body
        |> Enum.take(truncated_count)
        |> Enum.map(&Blocks.get_signed_block/1)
        |> Enum.map_join(&create_block_response_chunk/1)

      Libp2pPort.send_response(message_id, response_chunk)
    end
  end

  defp handle_req(protocol, _message_id, _message) do
    # This should never happen, since Libp2p only accepts registered protocols
    Logger.error("Unsupported protocol: #{protocol}")
    :ok
  end

  # TODO: header size can be retrieved from the schema
  defp decode_request(bytes, ssz_schema, decoded_size) do
    with {:ok, ssz_snappy_request} <- decode_size_header(decoded_size, bytes),
         {:ok, ssz_request} <- Snappy.decompress(ssz_snappy_request) do
      SszEx.decode(ssz_request, ssz_schema)
    end
  end

  defp decode_size_header(header, <<header, rest::binary>>), do: {:ok, rest}
  defp decode_size_header(_, ""), do: {:error, "empty message"}
  defp decode_size_header(_, _), do: {:error, "invalid message"}

  @spec encode_response({any(), SszEx.schema()} | struct(), binary()) ::
          {:ok, binary()} | {:error, String.t()}
  defp encode_response(response, context_bytes \\ <<>>)

  defp encode_response(%ssz_schema{} = response, context_bytes),
    do: encode_response({response, ssz_schema}, context_bytes)

  defp encode_response({response, ssz_schema}, context_bytes) do
    with {:ok, ssz_response} <- SszEx.encode(response, ssz_schema),
         size_header = byte_size(ssz_response) |> P2P.Utils.encode_varint(),
         {:ok, ssz_snappy_response} <- Snappy.compress(ssz_response) do
      {:ok, Enum.join([<<0>>, context_bytes, size_header, ssz_snappy_response])}
    end
  end

  @spec encode_error_response(1..255, String.t()) :: binary()
  def encode_error_response(status_code, error_message) do
    # NOTE: error_message == SszEx.encode(error_message) in this case, so we skip it
    size_header = error_message |> byte_size() |> P2P.Utils.encode_varint()
    {:ok, snappy_message} = Snappy.compress(error_message)
    <<status_code>> <> size_header <> snappy_message
  end

  # TODO: respond this on invalid request
  def invalid_request, do: encode_error_response(1, "Invalid Request")
  def server_error, do: encode_error_response(2, "Server Error")
  def resource_unavailable, do: encode_error_response(3, "Resource Unavailable")

  defp create_block_response_chunk({:ok, block}) do
    fork_context = BeaconChain.get_fork_digest_for_slot(block.message.slot)

    case encode_response(block, fork_context) do
      {:ok, chunk} -> chunk
      {:error, _} -> server_error()
    end
  end

  defp create_block_response_chunk({:error, _}), do: server_error()
  defp create_block_response_chunk(:not_found), do: resource_unavailable()
  defp create_block_response_chunk(:empty_slot), do: <<>>
end
