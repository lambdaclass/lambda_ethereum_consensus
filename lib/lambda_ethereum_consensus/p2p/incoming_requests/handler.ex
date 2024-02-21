defmodule LambdaEthereumConsensus.P2P.IncomingRequests.Handler do
  @moduledoc """
  This module handles Req/Resp domain requests.
  """
  require Logger

  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.{Libp2pPort, P2P}
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks

  require Logger

  # This is the `Resource Unavailable` error message
  # TODO: compute this and other messages at runtime
  @error_message_resource_unavailable "Resource Unavailable"
  # This is the `Server Error` error message
  # TODO: compute this and other messages at runtime
  @error_message_server_error "Server Error"

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
         {:ok, payload} <- Ssz.to_ssz(current_status),
         {:ok, payload} <- Snappy.compress(payload) do
      Libp2pPort.send_response(message_id, <<0, 84>> <> payload)
    end
  end

  defp handle_req("goodbye/1/ssz_snappy", message_id, message) do
    with {:ok, goodbye_reason} <- decode_request(message, TypeAliases.uint64(), 8),
         Logger.debug("[Goodbye] reason: #{goodbye_reason}"),
         {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2pPort.send_response(message_id, <<0, 8>> <> payload)
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
         {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2pPort.send_response(message_id, <<0, 8>> <> payload)
    end
  end

  defp handle_req("metadata/2/ssz_snappy", message_id, _message) do
    # NOTE: there's no request content so we just ignore it
    with metadata <- P2P.Metadata.get_metadata(),
         {:ok, metadata_ssz} <- Ssz.to_ssz(metadata),
         {:ok, payload} <- Snappy.compress(metadata_ssz) do
      Libp2pPort.send_response(message_id, <<0, 17>> <> payload)
    end
  end

  defp handle_req("beacon_blocks_by_range/2/ssz_snappy", message_id, message) do
    with {:ok, request} <- decode_request(message, Types.BeaconBlocksByRangeRequest, 24) do
      %{start_slot: start_slot, count: count} = request

      "[Received BlocksByRange Request] requested slots #{start_slot} to #{start_slot + count - 1}"
      |> Logger.info()

      count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      slot_coverage = start_slot + (count - 1)

      blocks =
        start_slot..slot_coverage
        |> Enum.map(&BlockDb.get_block_by_slot/1)

      response_chunk =
        blocks
        |> Enum.map_join(&create_block_response_chunk/1)

      Libp2pPort.send_response(message_id, response_chunk)
    end
  end

  defp handle_req("beacon_blocks_by_root/2/ssz_snappy", message_id, message) do
    with {:ok, request} <- decode_request(message, Types.BeaconBlocksByRootRequest, 24) do
      %{body: body} = request

      count =
        length(body)
        |> min(ChainSpec.get("MAX_REQUEST_BLOCKS"))

      "[Received BlocksByRoot Request] requested #{count} number of blocks"
      |> Logger.info()

      response_chunk =
        body
        |> Enum.slice(0..(count - 1))
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

  defp create_block_response_chunk({:ok, block}) do
    with {:ok, ssz_signed_block} <- Ssz.to_ssz(block),
         {:ok, snappy_ssz_signed_block} <- Snappy.compress(ssz_signed_block) do
      fork_context = BeaconChain.get_fork_digest_for_slot(block.message.slot)

      size_header =
        ssz_signed_block
        |> byte_size()
        |> P2P.Utils.encode_varint()

      <<0>> <> fork_context <> size_header <> snappy_ssz_signed_block
    else
      {:error, _} ->
        ## TODO: Add SSZ encoding
        size_header =
          @error_message_server_error
          |> byte_size()
          |> P2P.Utils.encode_varint()

        {:ok, snappy_message} = Snappy.compress(@error_message_server_error)
        <<2>> <> size_header <> snappy_message
    end
  end

  defp create_block_response_chunk({:error, _}) do
    ## TODO: Add SSZ encoding
    size_header =
      @error_message_resource_unavailable
      |> byte_size()
      |> P2P.Utils.encode_varint()

    {:ok, snappy_message} = Snappy.compress(@error_message_resource_unavailable)
    <<3>> <> size_header <> snappy_message
  end

  defp create_block_response_chunk(:not_found) do
    ## TODO: Add SSZ encoding
    size_header =
      @error_message_resource_unavailable
      |> byte_size()
      |> P2P.Utils.encode_varint()

    {:ok, snappy_message} = Snappy.compress(@error_message_resource_unavailable)
    <<3>> <> size_header <> snappy_message
  end

  defp create_block_response_chunk(:empty_slot), do: <<>>

  defp decode_size_header(header, <<header, rest::binary>>), do: {:ok, rest}
  defp decode_size_header(_, ""), do: {:error, "empty message"}
  defp decode_size_header(_, _), do: {:error, "invalid message"}
end
