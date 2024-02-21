defmodule LambdaEthereumConsensus.P2P.BlockDownloader do
  @moduledoc """
  This module requests blocks from peers.
  """
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.{Libp2pPort, P2P}
  alias LambdaEthereumConsensus.SszEx
  require Logger

  @blocks_by_range_protocol_id "/eth2/beacon_chain/req/beacon_blocks_by_range/2/ssz_snappy"
  @blocks_by_root_protocol_id "/eth2/beacon_chain/req/beacon_blocks_by_root/2/ssz_snappy"

  # Requests to peers might fail for various reasons,
  # for example they might not support the protocol or might not reply
  # so we want to try again with a different peer
  @default_retries 5

  @spec request_blocks_by_slot(Types.slot(), integer(), integer()) ::
          {:ok, [Types.SignedBeaconBlock.t()]} | {:error, any()}
  def request_blocks_by_slot(slot, count, retries \\ @default_retries)

  def request_blocks_by_slot(_slot, 0, _retries), do: {:ok, []}

  def request_blocks_by_slot(slot, count, retries) do
    Logger.debug("Requesting block", slot: slot)

    # TODO: handle no-peers asynchronously?
    peer_id = get_some_peer()

    request = encode_request(%Types.BeaconBlocksByRangeRequest{start_slot: slot, count: count})

    with {:ok, response_chunk} <-
           Libp2pPort.send_request(peer_id, @blocks_by_range_protocol_id, request),
         {:ok, chunks} <- parse_response(response_chunk),
         {:ok, blocks} <- decode_chunks(chunks),
         :ok <- verify_batch(blocks, slot, count) do
      tags = %{result: "success", type: "by_slot", reason: "success"}
      :telemetry.execute([:network, :request], %{blocks: count}, tags)
      {:ok, blocks}
    else
      {:error, reason} when retries > 0 ->
        tags = %{type: "by_slot", reason: parse_reason(reason)}
        P2P.Peerbook.penalize_peer(peer_id)
        :telemetry.execute([:network, :request], %{blocks: 0}, Map.put(tags, :result, "retry"))
        Logger.debug("Retrying request for block", slot: slot)
        request_blocks_by_slot(slot, count, retries - 1)

      {:error, reason} when retries == 0 ->
        P2P.Peerbook.penalize_peer(peer_id)
        tags = %{type: "by_slot", reason: parse_reason(reason)}
        :telemetry.execute([:network, :request], %{blocks: 0}, Map.put(tags, :result, "error"))
        {:error, reason}
    end
  end

  @spec request_block_by_root(Types.root(), integer()) ::
          {:ok, Types.SignedBeaconBlock.t()} | {:error, binary()}
  def request_block_by_root(root, retries \\ @default_retries) do
    with {:ok, [block]} <- request_blocks_by_root([root], retries) do
      {:ok, block}
    end
  end

  @spec request_blocks_by_root([Types.root()], integer()) ::
          {:ok, [Types.SignedBeaconBlock.t()]} | {:error, binary()}
  def request_blocks_by_root(roots, retries \\ @default_retries)

  def request_blocks_by_root([], _retries), do: {:ok, []}

  def request_blocks_by_root(roots, retries) do
    Logger.debug("Requesting block for roots #{Enum.map_join(roots, ", ", &Base.encode16/1)}")

    peer_id = get_some_peer()

    request = encode_request(roots, {:list, TypeAliases.root(), 999_999})

    with {:ok, response_chunk} <-
           Libp2pPort.send_request(peer_id, @blocks_by_root_protocol_id, request),
         {:ok, chunks} <- parse_response(response_chunk),
         {:ok, blocks} <- decode_chunks(chunks) do
      tags = %{result: "success", type: "by_root", reason: "success"}
      :telemetry.execute([:network, :request], %{blocks: length(roots)}, tags)
      {:ok, blocks}
    else
      {:error, reason} ->
        tags = %{type: "by_root", reason: parse_reason(reason)}
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          :telemetry.execute([:network, :request], %{blocks: 0}, Map.put(tags, :result, "retry"))

          Logger.debug(
            "Retrying request for blocks with roots #{Enum.map_join(roots, ", ", &Base.encode16/1)}"
          )

          request_blocks_by_root(roots, retries - 1)
        else
          :telemetry.execute([:network, :request], %{blocks: 0}, Map.put(tags, :result, "error"))
          {:error, reason}
        end
    end
  end

  @spec parse_response(binary) ::
          {:ok, [binary()]} | {:error, binary()}
  def parse_response(response_chunk) do
    fork_context = BeaconChain.get_fork_digest()

    case response_chunk do
      <<>> ->
        {:error, "unexpected EOF"}

      <<0, ^fork_context::binary-size(4)>> <> rest ->
        chunks = rest |> :binary.split(<<0, fork_context::binary-size(4)>>, [:global])
        {:ok, chunks}

      <<0, wrong_context::binary-size(4)>> <> _ ->
        {:error, "wrong context: #{Base.encode16(wrong_context)}"}

      <<code>> <> message ->
        error_response(code, message)
    end
  end

  defp encode_request(%ssz_schema{} = payload), do: encode_request(payload, ssz_schema)

  defp encode_request(payload, ssz_schema) do
    {:ok, encoded_payload} = payload |> SszEx.encode(ssz_schema)

    size_header =
      encoded_payload
      |> byte_size()
      |> P2P.Utils.encode_varint()

    {:ok, compressed_payload} = encoded_payload |> Snappy.compress()

    size_header <> compressed_payload
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

  @spec decode_chunks([binary()]) :: {:ok, [Types.SignedBeaconBlock.t()]} | {:error, binary()}
  defp decode_chunks(chunks) do
    # TODO: handle errors
    blocks =
      chunks
      |> Enum.map(&decode_chunk/1)
      |> Enum.map(fn
        {:ok, block} -> block
        {:error, _reason} -> nil
      end)
      |> Enum.filter(&(&1 != nil))

    case blocks do
      [] ->
        Logger.error("All blocks decoding failed")
        {:error, "all blocks decoding failed"}

      blocks ->
        {:ok, blocks}
    end
  end

  @spec decode_chunk(binary()) :: {:ok, Types.SignedBeaconBlock.t()} | {:error, binary()}
  defp decode_chunk(chunk) do
    {_size, rest} = P2P.Utils.decode_varint(chunk)

    with {:ok, decompressed} <- Snappy.decompress(rest),
         {:ok, signed_block} <-
           decompressed
           |> Ssz.from_ssz(Types.SignedBeaconBlock) do
      {:ok, signed_block}
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
