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

      Logger.info("[BlocksByRange] requested #{count} slots, starting from #{start_slot}")

      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      end_slot = start_slot + (truncated_count - 1)

      response_chunk =
        start_slot..end_slot
        |> Enum.map(&BlockDb.get_block_by_slot/1)
        |> Enum.map(&map_block_result/1)
        |> Enum.reject(&(&1 == :skip))
        |> encode_response_chunks()

      Libp2pPort.send_response(message_id, response_chunk)
    end
  end

  defp handle_req("beacon_blocks_by_root/2/ssz_snappy", message_id, message) do
    with {:ok, %{body: body}} <- decode_request(message, Types.BeaconBlocksByRootRequest, 24) do
      count = length(body)
      Logger.info("[BlocksByRoot] requested #{count} number of blocks")
      truncated_count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      response_chunk =
        body
        |> Enum.take(truncated_count)
        |> Enum.map(&Blocks.get_signed_block/1)
        |> Enum.map(&map_block_result/1)
        |> Enum.reject(&(&1 == :skip))
        |> encode_response_chunks()

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

  ## Request decoding

  # TODO: header size can be retrieved from the schema
  def decode_request(bytes, ssz_schema, decoded_size) do
    with {:ok, ssz_snappy_request} <- decode_size_header(decoded_size, bytes),
         {:ok, ssz_request} <- Snappy.decompress(ssz_snappy_request) do
      SszEx.decode(ssz_request, ssz_schema)
    end
  end

  defp decode_size_header(header, <<header, rest::binary>>), do: {:ok, rest}
  defp decode_size_header(_, ""), do: {:error, "empty message"}
  defp decode_size_header(_, _), do: {:error, "invalid message"}

  ## Response encoding

  @type context_bytes :: binary()
  @type encodable_response :: {any(), SszEx.schema()} | struct()
  @type error_code :: 1..255
  @type error_message :: String.t()

  @type response_payload ::
          {:ok, {encodable_response(), context_bytes()}}
          | {:error, {error_code(), error_message()}}

  @spec encode_response_chunks([response_payload()]) :: binary()
  def encode_response_chunks(responses) do
    Enum.map_join(responses, fn
      {:ok, {response, context_bytes}} -> encode_response(response, context_bytes)
      {:error, {code, message}} -> encode_error_response(code, message)
    end)
  end

  @spec encode_response(encodable_response(), context_bytes()) ::
          {:ok, binary()} | {:error, String.t()}
  def encode_response(response, context_bytes \\ <<>>)

  def encode_response(%ssz_schema{} = response, context_bytes),
    do: encode_response({response, ssz_schema}, context_bytes)

  def encode_response({response, ssz_schema}, context_bytes) do
    with {:ok, ssz_response} <- SszEx.encode(response, ssz_schema),
         size_header = byte_size(ssz_response) |> P2P.Utils.encode_varint(),
         {:ok, ssz_snappy_response} <- Snappy.compress(ssz_response) do
      {:ok, Enum.join([<<0>>, context_bytes, size_header, ssz_snappy_response])}
    end
  end

  @spec encode_error_response(error_code(), error_message()) :: binary()
  def encode_error_response(status_code, error_message) do
    # NOTE: error_message == SszEx.encode(error_message) in this case, so we skip it
    size_header = error_message |> byte_size() |> P2P.Utils.encode_varint()
    {:ok, snappy_message} = Snappy.compress(error_message)
    <<status_code>> <> size_header <> snappy_message
  end
end
