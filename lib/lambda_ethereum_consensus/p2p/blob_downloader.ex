defmodule LambdaEthereumConsensus.P2P.BlobDownloader do
  @moduledoc """
  This module requests blocks from peers.
  """
  require Logger

  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.P2P
  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.Store
  alias Types.BlobSidecar
  alias Types.Store

  @blobs_by_range_protocol_id "/eth2/beacon_chain/req/blob_sidecars_by_range/1/ssz_snappy"
  @blobs_by_root_protocol_id "/eth2/beacon_chain/req/blob_sidecars_by_root/1/ssz_snappy"

  @type on_blobs :: (Store.t(), {:ok, [BlobSidecar.t()]} | {:error, any()} -> :ok)
  @type on_blob :: (Store.t(), {:ok, BlobSidecar.t()} | {:error, any()} -> :ok)

  # Requests to peers might fail for various reasons,
  # for example they might not support the protocol or might not reply
  # so we want to try again with a different peer
  @default_retries 5

  @spec request_blobs_by_range(Types.slot(), non_neg_integer(), on_blobs(), non_neg_integer()) ::
          :ok
  def request_blobs_by_range(slot, count, on_blobs, retries \\ @default_retries)

  def request_blobs_by_range(_slot, 0, _on_blobs, _retries), do: {:ok, []}

  def request_blobs_by_range(slot, count, on_blobs, retries) do
    Logger.debug("Requesting blobs", slot: slot)

    # TODO: handle no-peers asynchronously?
    peer_id = get_some_peer()

    # NOTE: BeaconBlocksByRangeRequest == BlobSidecarsByRangeRequest
    request =
      %Types.BeaconBlocksByRangeRequest{start_slot: slot, count: count}
      |> ReqResp.encode_request()

    Libp2pPort.send_async_request(peer_id, @blobs_by_range_protocol_id, request, fn store,
                                                                                    response ->
      Metrics.handler_span(
        "response_handler",
        "blob_sidecars_by_range",
        fn ->
          handle_blobs_by_range_response(store, response, peer_id, count, slot, retries, on_blobs)
        end
      )
    end)
  end

  defp handle_blobs_by_range_response(store, response, peer_id, count, slot, retries, on_blobs) do
    with {:ok, response_message} <- response,
         {:ok, blobs} <- ReqResp.decode_response(response_message, BlobSidecar),
         :ok <- verify_batch(blobs, slot, count) do
      on_blobs.(store, {:ok, blobs})
    else
      {:error, reason} ->
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          Logger.debug("Retrying request for #{count} blobs", slot: slot)
          request_blobs_by_range(slot, count, on_blobs, retries - 1)
          {:ok, store}
        else
          on_blobs.(store, {:error, reason})
        end
    end
  end

  @spec request_blob_by_root(Types.BlobIdentifier.t(), on_blob(), non_neg_integer()) :: :ok
  def request_blob_by_root(identifier, on_blob, retries \\ @default_retries) do
    request_blobs_by_root(
      [identifier],
      fn store, response -> on_blob.(store, flatten_response(response)) end,
      retries
    )
  end

  @spec request_blobs_by_root([Types.BlobIdentifier.t()], on_blobs(), non_neg_integer()) :: :ok
  def request_blobs_by_root(identifiers, on_blobs, retries \\ @default_retries)

  def request_blobs_by_root([], _on_blobs, _retries), do: {:ok, []}

  def request_blobs_by_root(identifiers, on_blobs, retries) do
    Logger.debug("Requesting #{length(identifiers)} blobs.")

    peer_id = get_some_peer()

    request = ReqResp.encode_request({identifiers, TypeAliases.blob_sidecars_by_root_request()})

    Libp2pPort.send_async_request(peer_id, @blobs_by_root_protocol_id, request, fn store,
                                                                                   response ->
      Metrics.handler_span(
        "response_handler",
        "blob_sidecars_by_root",
        fn -> handle_blobs_by_root(store, response, peer_id, identifiers, retries, on_blobs) end
      )
    end)
  end

  def handle_blobs_by_root(store, response, peer_id, identifiers, retries, on_blobs) do
    with {:ok, response_message} <- response,
         {:ok, blobs} <- ReqResp.decode_response(response_message, BlobSidecar) do
      on_blobs.(store, {:ok, blobs})
    else
      {:error, reason} ->
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          Logger.debug("Retrying request for blobs.")
          request_blobs_by_root(identifiers, on_blobs, retries - 1)
          {:ok, store}
        else
          on_blobs.(store, {:error, reason})
        end
    end
  end

  defp get_some_peer() do
    case P2P.Peerbook.get_some_peer() do
      nil ->
        Process.sleep(100)
        get_some_peer()

      peer_id ->
        peer_id
    end
  end

  defp verify_batch(blocks, start_slot, count) do
    end_slot = start_slot + count

    if Enum.all?(blocks, fn %{signed_block_header: %{message: %{slot: slot}}} ->
         start_slot <= slot and slot < end_slot
       end) do
      :ok
    else
      {:error, "blob outside requested slot range"}
    end
  end

  defp flatten_response({:ok, [blob]}), do: {:ok, blob}
  defp flatten_response(other), do: other
end
