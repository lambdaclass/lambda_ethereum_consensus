defmodule LambdaEthereumConsensus.P2P.IncomingRequests.Handler do
  @moduledoc """
  This module handles Req/Resp domain requests.
  """
  require Logger
  alias LambdaEthereumConsensus.{Libp2pPort, P2P}
  alias LambdaEthereumConsensus.Store.BlockStore

  # This is the `ForkDigest` for mainnet in the capella fork
  # TODO: compute this at runtime
  @fork_context "BBA4DA96" |> Base.decode16!()

  # This is the `Resource Unavailable` error message
  # TODO: compute this and other messages at runtime
  @error_message_resource_unavailable "Resource Unavailable"
  # This is the `Server Error` error message
  # TODO: compute this and other messages at runtime
  @error_message_server_error "Server Error"

  def handle(name, message_id, message) do
    case handle_req(name, message_id, message) do
      :ok -> :ok
      :not_implemented -> :ok
      {:error, error} -> Logger.error("[#{name}] Request error: #{inspect(error)}")
    end
  end

  @spec handle_req(String.t(), String.t(), binary()) ::
          :ok | :not_implemented | {:error, binary()}
  defp handle_req("status/1/ssz_snappy", message_id, message) do
    # hardcoded response from random peer
    current_status = %SszTypes.StatusMessage{
      fork_digest: Base.decode16!("BBA4DA96"),
      finalized_root:
        Base.decode16!("7715794499C07D9954DD223EC2C6B846D3BAB27956D093000FADC1B8219F74D4"),
      finalized_epoch: 228_168,
      head_root:
        Base.decode16!("D62A74AE0F933224133C5E6E1827A2835A1E705F0CDFEE3AD25808DDEA5572DB"),
      head_slot: 7_301_450
    }

    with <<84, snappy_status::binary>> <- message,
         {:ok, ssz_status} <- Snappy.decompress(snappy_status),
         {:ok, status} <- Ssz.from_ssz(ssz_status, SszTypes.StatusMessage),
         status
         |> inspect(limit: :infinity)
         |> then(&"[Status] '#{&1}'")
         |> Logger.debug(),
         {:ok, payload} <- Ssz.to_ssz(current_status),
         {:ok, payload} <- Snappy.compress(payload) do
      Libp2pPort.send_response(message_id, <<0, 84>> <> payload)
    end
  end

  defp handle_req("goodbye/1/ssz_snappy", message_id, message) do
    with <<8, snappy_code_le::binary>> <- message,
         {:ok, code_le} <- Snappy.decompress(snappy_code_le),
         :ok <-
           code_le
           |> :binary.decode_unsigned(:little)
           |> then(&Logger.debug("[Goodbye] reason: #{&1}")),
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
    end
  end

  defp handle_req("ping/1/ssz_snappy", message_id, message) do
    # Values are hardcoded
    with <<8, seq_number_le::binary>> <- message,
         {:ok, decompressed} <-
           Snappy.decompress(seq_number_le),
         decompressed
         |> :binary.decode_unsigned(:little)
         |> then(&"[Ping] seq_number: #{&1}")
         |> Logger.debug(),
         {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2pPort.send_response(message_id, <<0, 8>> <> payload)
    end
  end

  defp handle_req("metadata/2/ssz_snappy", message_id, _message) do
    # Values are hardcoded
    with {:ok, payload} <-
           <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>
           |> Snappy.compress() do
      Libp2pPort.send_response(message_id, <<0, 17>> <> payload)
    end
  end

  defp handle_req("beacon_blocks_by_range/2/ssz_snappy", message_id, message) do
    with <<24, snappy_blocks_by_range_request::binary>> <- message,
         {:ok, ssz_blocks_by_range_request} <- Snappy.decompress(snappy_blocks_by_range_request),
         {:ok, blocks_by_range_request} <-
           Ssz.from_ssz(ssz_blocks_by_range_request, SszTypes.BeaconBlocksByRangeRequest) do
      ## TODO: there should be check that the `start_slot` is not older than the `oldest_slot_with_block`
      %SszTypes.BeaconBlocksByRangeRequest{start_slot: start_slot, count: count} =
        blocks_by_range_request

      "[Received BlocksByRange Request] requested slots #{start_slot} to #{start_slot + count - 1}"
      |> Logger.info()

      count = min(count, ChainSpec.get("MAX_REQUEST_BLOCKS"))

      slot_coverage = start_slot + (count - 1)

      blocks =
        start_slot..slot_coverage
        |> Enum.map(&BlockStore.get_block_by_slot/1)

      response_chunk =
        blocks
        |> Enum.map_join(&create_block_response_chunk/1)

      Libp2pPort.send_response(message_id, response_chunk)
    end
  end

  defp parse_message_size(<<24, request::binary>>), do: {:ok, request}
  defp parse_message_size(_), do: {:error, "invalid request"}

  defp handle_req("beacon_blocks_by_root/2/ssz_snappy", message_id, message) do
    with {:ok, snappy_blocks_by_root_request} <- parse_message_size(message),
         {:ok, ssz_blocks_by_root_request} <- Snappy.decompress(snappy_blocks_by_root_request),
         {:ok, blocks_by_root_request} <-
           Ssz.from_ssz(ssz_blocks_by_root_request, SszTypes.BeaconBlocksByRootRequest) do
      ## TODO: there should be check that the `start_slot` is not older than the `oldest_slot_with_block`
      %SszTypes.BeaconBlocksByRootRequest{body: body} =
        blocks_by_root_request

      count =
        length(body)
        |> min(ChainSpec.get("MAX_REQUEST_BLOCKS"))

      "[Received BlocksByRoot Request] requested #{count} number of blocks"
      |> Logger.info()

      response_chunk =
        body
        |> Enum.slice(0..(count - 1))
        |> Enum.map(&BlockStore.get_block/1)
        |> Enum.map_join(&create_block_response_chunk/1)

      Libp2pPort.send_response(message_id, response_chunk)
    end
  end

  defp handle_req(protocol, _message_id, _message) do
    # This should never happen, since Libp2p only accepts registered protocols
    Logger.error("Unsupported protocol: #{protocol}")
    :ok
  end

  defp create_block_response_chunk({:ok, block}) do
    with {:ok, ssz_signed_block} <- Ssz.to_ssz(block),
         {:ok, snappy_ssz_signed_block} <- Snappy.compress(ssz_signed_block) do
      size_header =
        ssz_signed_block
        |> byte_size()
        |> P2P.Utils.encode_varint()

      <<0>> <> @fork_context <> size_header <> snappy_ssz_signed_block
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
end
