defmodule LambdaEthereumConsensus.P2P.BlockDownloader do
  @moduledoc """
  This module requests blocks from peers.
  """
  alias LambdaEthereumConsensus.P2P.Peerbook
  use GenStage

  @protocol_id "/eth2/beacon_chain/req/beacon_blocks_by_range/2/ssz_snappy"

  @impl true
  def init([host]) do
    {:producer, host}
  end

  @impl true
  def handle_demand(incoming_demand, host) do
    # Capella fork slot
    # TODO: get missing slots from DB
    start_slot = 6_209_536

    # TODO: handle no-peers asynchronously?
    peer_id = get_some_peer()

    payload = %SszTypes.BeaconBlocksByRangeRequest{
      start_slot: start_slot,
      # TODO: we need to refactor the Snappy library to return
      # the remaining buffer when decompressing
      count: 1
    }

    # This should never fail
    {:ok, encoded_payload} = payload |> Ssz.to_ssz()

    # This would be a protobuf varint
    size_header = <<byte_size(encoded_payload)>>

    # This should never fail
    {:ok, compressed_payload} = encoded_payload |> Snappy.compress()

    with {:ok, stream} <-
           Libp2p.host_new_stream(host, peer_id, @protocol_id),
         :ok <- Libp2p.stream_write(stream, size_header <> compressed_payload),
         :ok <- Libp2p.stream_close_write(stream),
         {:ok, chunk} <- read_response(stream),
         {:ok, block} <- decode_response(chunk) do
      {:noreply, [wrap_message(block)], host}
    else
      {:error, _reason} ->
        handle_demand(incoming_demand, host)
    end
  end

  defp read_response(stream) do
    result =
      stream
      |> Libp2p.Stream.from()
      |> Enum.reduce({:ok, ""}, fn
        {:ok, chunk}, {:ok, acc} -> {:ok, acc <> chunk}
        {:error, reason}, _ -> {:error, reason}
      end)

    case result do
      {:ok, ""} -> {:error, "unexpected EOF"}
      {:ok, <<0, chunk::binary>>} -> {:ok, chunk}
      {:ok, <<code, message::binary>>} -> error_response(code, message)
      err -> err
    end
  end

  defp error_response(error_code, ""), do: {:error, "error code: #{error_code}"}

  defp error_response(error_code, error_message),
    do: {:error, "error code: #{error_code}, with message: #{error_message}"}

  defp decode_response(response) do
    with {:ok, chunk} <- Snappy.decompress(response) do
      chunk
      |> Ssz.from_ssz(SszTypes.SignedBeaconBlock)
    end
  end

  defp wrap_message(msg) do
    %Broadway.Message{
      data: msg,
      acknowledger: Broadway.NoopAcknowledger.init()
    }
  end

  defp get_some_peer() do
    case Peerbook.get_some_peer() do
      nil ->
        Process.sleep(1000)
        get_some_peer()

      peer_id ->
        peer_id
    end
  end
end
