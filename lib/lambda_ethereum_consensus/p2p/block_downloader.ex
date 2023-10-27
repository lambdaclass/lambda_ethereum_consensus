defmodule LambdaEthereumConsensus.P2P.BlockDownloader do
  @moduledoc """
  This module requests blocks from peers.
  """
  alias LambdaEthereumConsensus.{Libp2pPort, P2P}
  require Logger

  @blocks_by_range_protocol_id "/eth2/beacon_chain/req/beacon_blocks_by_range/2/ssz_snappy"
  @blocks_by_root_protocol_id "/eth2/beacon_chain/req/beacon_blocks_by_root/2/ssz_snappy"

  # This is the `ForkDigest` for mainnet in the capella fork
  # TODO: compute this at runtime
  @fork_context "BBA4DA96" |> Base.decode16!()

  # Requests to peers might fail for various reasons,
  # for example they might not support the protocol or might not reply
  # so we want to try again with a different peer
  @default_retries 3

  @spec request_block_by_slot(SszTypes.slot(), integer()) ::
          {:ok, SszTypes.SignedBeaconBlock.t()} | {:error, binary()}
  def request_block_by_slot(slot, retries \\ @default_retries) do
    Logger.debug("requesting block for slot #{slot}")

    # TODO: handle no-peers asynchronously?
    peer_id = get_some_peer()

    payload =
      %SszTypes.BeaconBlocksByRangeRequest{
        start_slot: slot,
        # TODO: we need to refactor the Snappy library to return
        # the remaining buffer when decompressing
        count: 1
      }

    # This should never fail
    {:ok, encoded_payload} = payload |> Ssz.to_ssz()

    size_header =
      encoded_payload
      |> byte_size()
      |> P2P.Utils.encode_varint()

    # This should never fail
    {:ok, compressed_payload} = encoded_payload |> Snappy.compress()

    with {:ok, response_chunk} <-
           Libp2pPort.send_request(
             peer_id,
             @blocks_by_range_protocol_id,
             size_header <> compressed_payload
           ),
         {:ok, payload} <- parse_chunk(response_chunk),
         {:ok, block} <- decode_response(payload) do
      :telemetry.execute([:network, :request], %{}, %{result: "success", type: "by_slot"})
      {:ok, block}
    else
      {:error, reason} ->
        if retries > 0 do
          :telemetry.execute([:network, :request], %{}, %{result: "retry", type: "by_slot"})
          Logger.debug("Retrying request for block with slot #{slot}")
          request_block_by_slot(slot, retries - 1)
        else
          :telemetry.execute([:network, :request], %{}, %{result: "error", type: "by_slot"})
          {:error, reason}
        end
    end
  end

  @spec request_block_by_root(SszTypes.root(), integer()) ::
          {:ok, SszTypes.SignedBeaconBlock.t()} | {:error, binary()}
  def request_block_by_root(root, retries \\ @default_retries) do
    Logger.debug("requesting block for root #{Base.encode16(root)}")

    peer_id = get_some_peer()

    # TODO ssz encode array of roots
    # {:ok, encoded_payload} = payload |> Ssz.to_ssz()
    encoded_payload = root

    size_header =
      encoded_payload
      |> byte_size()
      |> P2P.Utils.encode_varint()

    {:ok, compressed_payload} = encoded_payload |> Snappy.compress()

    with {:ok, response_chunk} <-
           Libp2pPort.send_request(
             peer_id,
             @blocks_by_root_protocol_id,
             size_header <> compressed_payload
           ),
         {:ok, payload} <- parse_chunk(response_chunk),
         {:ok, block} <- decode_response(payload) do
      :telemetry.execute([:network, :request], %{}, %{result: "success", type: "by_root"})
      {:ok, block}
    else
      {:error, reason} ->
        if retries > 0 do
          :telemetry.execute([:network, :request], %{}, %{result: "retry", type: "by_root"})
          Logger.debug("Retrying request for block with root #{Base.encode16(root)}")
          request_block_by_root(root, retries - 1)
        else
          :telemetry.execute([:network, :request], %{}, %{result: "error", type: "by_root"})
          {:error, reason}
        end
    end
  end

  defp parse_chunk(response_chunk) do
    fork_context = @fork_context

    case response_chunk do
      "" ->
        {:error, "unexpected EOF"}

      <<0, ^fork_context::binary-size(4)>> <> chunk ->
        {:ok, chunk}

      <<0, wrong_context::binary-size(4)>> <> _ ->
        {:error, "wrong context: #{Base.encode16(wrong_context)}"}

      <<code>> <> message ->
        error_response(code, message)
    end
  end

  defp error_response(error_code, ""), do: {:error, "error code: #{error_code}"}

  defp error_response(error_code, error_message) do
    {_size, rest} = P2P.Utils.decode_varint(error_message)

    case rest |> Snappy.decompress() do
      {:ok, message} ->
        {:error, "error code: #{error_code}, with message: #{message}"}

      {:error, _reason} ->
        message = error_message |> Base.encode16()
        {:error, "error code: #{error_code}, with raw message: '#{message}'"}
    end
  end

  defp decode_response(response) do
    {_size, rest} = P2P.Utils.decode_varint(response)

    with {:ok, chunk} <- Snappy.decompress(rest) do
      chunk |> Ssz.from_ssz(SszTypes.SignedBeaconBlock)
    end
  end

  defp get_some_peer do
    case P2P.Peerbook.get_some_peer() do
      nil ->
        Process.sleep(1000)
        get_some_peer()

      peer_id ->
        peer_id
    end
  end
end
