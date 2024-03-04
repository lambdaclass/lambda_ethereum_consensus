defmodule LambdaEthereumConsensus.P2P.BlobDownloader do
  @moduledoc """
  This module requests blocks from peers.
  """
  require Logger

  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.{Libp2pPort, P2P}
  alias Types.BlobSidecar

  @blobs_by_range_protocol_id "/eth2/beacon_chain/req/blob_sidecars_by_range/1/ssz_snappy"
  @blobs_by_root_protocol_id "/eth2/beacon_chain/req/blob_sidecars_by_root/1/ssz_snappy"

  # Requests to peers might fail for various reasons,
  # for example they might not support the protocol or might not reply
  # so we want to try again with a different peer
  @default_retries 5

  @spec request_blobs_by_range(Types.slot(), non_neg_integer(), non_neg_integer()) ::
          {:ok, [BlobSidecar.t()]} | {:error, any()}
  def request_blobs_by_range(slot, count, retries \\ @default_retries)

  def request_blobs_by_range(_slot, 0, _retries), do: {:ok, []}

  def request_blobs_by_range(slot, count, retries) do
    Logger.debug("Requesting blobs", slot: slot)

    # TODO: handle no-peers asynchronously?
    peer_id = get_some_peer()

    # NOTE: BeaconBlocksByRangeRequest == BlobSidecarsByRangeRequest
    request =
      %Types.BeaconBlocksByRangeRequest{start_slot: slot, count: count}
      |> ReqResp.encode_request()

    with {:ok, response} <-
           Libp2pPort.send_request(peer_id, @blobs_by_range_protocol_id, request),
         {:ok, blobs} <- ReqResp.decode_response(response, BlobSidecar),
         :ok <- verify_batch(blobs, slot, count) do
      {:ok, blobs}
    else
      {:error, reason} ->
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          Logger.debug("Retrying request for #{count} blobs", slot: slot)
          request_blobs_by_range(slot, count, retries - 1)
        else
          {:error, reason}
        end
    end
  end

  @spec request_blob_by_root(Types.BlobIdentifier.t(), non_neg_integer()) ::
          {:ok, BlobSidecar.t()} | {:error, binary()}
  def request_blob_by_root(identifier, retries \\ @default_retries) do
    with {:ok, [blob]} <- request_blobs_by_root([identifier], retries) do
      {:ok, blob}
    end
  end

  @spec request_blobs_by_root([Types.BlobIdentifier.t()], non_neg_integer()) ::
          {:ok, [BlobSidecar.t()]} | {:error, binary()}
  def request_blobs_by_root(identifiers, retries \\ @default_retries)

  def request_blobs_by_root([], _retries), do: {:ok, []}

  def request_blobs_by_root(identifiers, retries) do
    Logger.debug("Requesting #{length(identifiers)} blobs.")

    peer_id = get_some_peer()

    request =
      %Types.BlobSidecarsByRootRequest{body: identifiers}
      |> ReqResp.encode_request()

    with {:ok, response} <-
           Libp2pPort.send_request(peer_id, @blobs_by_root_protocol_id, request),
         {:ok, blobs} <- ReqResp.decode_response(response, BlobSidecar) do
      {:ok, blobs}
    else
      {:error, reason} ->
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          Logger.debug("Retrying request for blobs.")
          request_blobs_by_root(identifiers, retries - 1)
        else
          {:error, reason}
        end
    end
  end

  defp get_some_peer do
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
end
