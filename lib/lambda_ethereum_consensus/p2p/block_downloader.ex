defmodule LambdaEthereumConsensus.P2P.BlockDownloader do
  @moduledoc """
  This module requests blocks from peers.
  """
  require Logger

  alias LambdaEthereumConsensus.P2P.ReqResp
  alias LambdaEthereumConsensus.{Libp2pPort, P2P}
  alias Types.SignedBeaconBlock

  @blocks_by_range_protocol_id "/eth2/beacon_chain/req/beacon_blocks_by_range/2/ssz_snappy"
  @blocks_by_root_protocol_id "/eth2/beacon_chain/req/beacon_blocks_by_root/2/ssz_snappy"

  # Requests to peers might fail for various reasons,
  # for example they might not support the protocol or might not reply
  # so we want to try again with a different peer
  @default_retries 5

  @spec request_blocks_by_range(Types.slot(), non_neg_integer(), non_neg_integer()) ::
          {:ok, [SignedBeaconBlock.t()]} | {:error, any()}
  def request_blocks_by_range(slot, count, retries \\ @default_retries)

  def request_blocks_by_range(_slot, 0, _retries), do: {:ok, []}

  def request_blocks_by_range(slot, count, retries) do
    Logger.debug("Requesting block", slot: slot)

    # TODO: handle no-peers asynchronously?
    peer_id = get_some_peer()

    request =
      ReqResp.encode_ok(%Types.BeaconBlocksByRangeRequest{start_slot: slot, count: count})

    with {:ok, response} <-
           Libp2pPort.send_request(peer_id, @blocks_by_range_protocol_id, request),
         {:ok, blocks} <- ReqResp.decode_response(response, SignedBeaconBlock),
         :ok <- verify_batch(blocks, slot, count) do
      tags = %{result: "success", type: "by_slot", reason: "success"}
      :telemetry.execute([:network, :request], %{blocks: count}, tags)
      {:ok, blocks}
    else
      {:error, reason} ->
        tags = %{type: "by_slot", reason: parse_reason(reason)}
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          :telemetry.execute([:network, :request], %{blocks: 0}, Map.put(tags, :result, "retry"))
          Logger.debug("Retrying request for #{count} blocks", slot: slot)
          request_blocks_by_range(slot, count, retries - 1)
        else
          :telemetry.execute([:network, :request], %{blocks: 0}, Map.put(tags, :result, "error"))
          {:error, reason}
        end
    end
  end

  @spec request_block_by_root(Types.root(), integer()) ::
          {:ok, SignedBeaconBlock.t()} | {:error, binary()}
  def request_block_by_root(root, retries \\ @default_retries) do
    with {:ok, [block]} <- request_blocks_by_root([root], retries) do
      {:ok, block}
    end
  end

  @spec request_blocks_by_root([Types.root()], integer()) ::
          {:ok, [SignedBeaconBlock.t()]} | {:error, binary()}
  def request_blocks_by_root(roots, retries \\ @default_retries)

  def request_blocks_by_root([], _retries), do: {:ok, []}

  def request_blocks_by_root(roots, retries) do
    Logger.debug("Requesting block for roots #{Enum.map_join(roots, ", ", &Base.encode16/1)}")

    peer_id = get_some_peer()

    request = ReqResp.encode_ok(%Types.BeaconBlocksByRootRequest{body: roots})

    with {:ok, response} <-
           Libp2pPort.send_request(peer_id, @blocks_by_root_protocol_id, request),
         {:ok, blocks} <- ReqResp.decode_response(response, SignedBeaconBlock) do
      tags = %{result: "success", type: "by_root", reason: "success"}
      :telemetry.execute([:network, :request], %{blocks: length(roots)}, tags)
      {:ok, blocks}
    else
      {:error, reason} ->
        tags = %{type: "by_root", reason: parse_reason(reason)}
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          :telemetry.execute([:network, :request], %{blocks: 0}, Map.put(tags, :result, "retry"))
          pretty_roots = Enum.map_join(roots, ", ", &Base.encode16/1)
          Logger.debug("Retrying request for blocks with roots #{pretty_roots}")
          request_blocks_by_root(roots, retries - 1)
        else
          :telemetry.execute([:network, :request], %{blocks: 0}, Map.put(tags, :result, "error"))
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

  defp parse_reason(reason) do
    case reason do
      "failed to dial" <> _ -> "failed to dial"
      res -> res
    end
  end

  defp verify_batch(blocks, start_slot, count) do
    end_slot = start_slot + count

    if Enum.all?(blocks, fn %{message: %{slot: slot}} ->
         start_slot <= slot and slot < end_slot
       end) do
      :ok
    else
      {:error, "block outside requested slot range"}
    end
  end
end
