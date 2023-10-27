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
  @default_retries 5

  @spec request_blocks_by_slot(SszTypes.slot(), integer(), integer()) ::
          {:ok, SszTypes.SignedBeaconBlock.t()} | {:error, binary()}
  def request_blocks_by_slot(slot, count, retries \\ @default_retries) do
    Logger.debug("requesting block for slot #{slot}")

    # TODO: handle no-peers asynchronously?
    peer_id = get_some_peer()

    payload =
      %SszTypes.BeaconBlocksByRangeRequest{
        start_slot: slot,
        # TODO: we need to refactor the Snappy library to return
        # the remaining buffer when decompressing
        count: count
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
         {:ok, chunks} <- read_response(response_chunk),
         {:ok, blocks} <- decode_chunks(chunks) do
      {:ok, blocks}
    else
      {:error, reason} ->
        if retries > 0 do
          Logger.debug("Retrying request for block with slot #{slot}")
          request_blocks_by_slot(slot, count, retries - 1)
        else
          {:error, reason}
        end
    end
  end

  @spec request_block_by_root(SszTypes.root(), integer()) ::
          {:ok, SszTypes.SignedBeaconBlock.t()} | {:error, binary()}
  def request_block_by_root(root, retries \\ @default_retries) do
    with {:ok, [block]} <- request_blocks_by_root([root], retries) do
      {:ok, block}
    end
  end

  @spec request_blocks_by_root([SszTypes.root()], integer()) ::
          {:ok, [SszTypes.SignedBeaconBlock.t()]} | {:error, binary()}
  def request_blocks_by_root(roots, retries \\ @default_retries) do
    Logger.debug("requesting block for roots #{Enum.map_join(roots, ", ", &Base.encode16/1)}")

    peer_id = get_some_peer()

    # TODO ssz encode array of roots
    # {:ok, encoded_payload} = payload |> Ssz.to_ssz()
    encoded_payload = Enum.join(roots)

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
         {:ok, chunks} <- read_response(response_chunk),
         {:ok, blocks} <- decode_chunks(chunks) do
      {:ok, blocks}
    else
      {:error, reason} ->
        if retries > 0 do
          Logger.debug(
            "Retrying request for block with roots #{Enum.map_join(roots, ", ", &Base.encode16/1)}"
          )

          request_blocks_by_root(roots, retries - 1)
        else
          {:error, reason}
        end
    end
  end

  @doc """
  Reads the response from a stream and returns a list of chunks.

  The stream should consist of the following format
    response  ::= <response_chunk>*
    response_chunk  ::= <result> | <context-bytes> | <chunk>
    result    ::= “0” | “1” | “2” | [“128” ... ”255”]

  We need to ensure that the context bytes correspond to the current fork digest
  """
  @spec read_response(Libp2p.stream()) :: {:ok, [binary()]} | {:error, binary()}
  def read_response(stream) do
    fork_context = @fork_context

    stream
    # Takes a list of N arbitrary binary chunks and returns a list of M <chunk>s
    # For example:
    # [<<0, fork_context, 1>>, <<2, 3>>, <<0, fork_context>>, <<4>>, <<5>>] -> [<<1, 2, 3>>, <<4, 5>>]
    |> Enum.reduce({:ok, []}, fn
      {:ok, <<0, ^fork_context::binary-size(4)>> <> chunk}, {:ok, acc} ->
        {:ok, [chunk | acc]}

      {:ok, <<>>}, {:ok, []} ->
        {:error, "unexpected EOF"}

      {:ok, <<0, wrong_context::binary-size(4)>> <> _}, {:ok, []} ->
        {:error, "wrong context: #{Base.encode16(wrong_context)}"}

      {:ok, <<code>> <> message} ->
        error_response(code, message)

      {:ok, chunk}, {:ok, [h | t]} ->
        {:ok, [h <> chunk | t]}

      {:error, reason}, {:ok, _acc} ->
        {:error, reason}

      _, {:error, reason} ->
        {:error, reason}

      _, _ ->
        {:error, "error dividing response into chunks"}
    end)
    |> case do
      {:ok, []} -> {:error, "no chunks"}
      {:ok, list} -> {:ok, Enum.reverse(list)}
      {:error, reason} -> {:error, reason}
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

  @spec decode_chunks([binary()]) :: {:ok, [SszTypes.SignedBeaconBlock.t()]} | {:error, binary()}
  defp decode_chunks(chunks) do
    results =
      chunks
      |> Enum.map(&decode_chunk/1)

    if Enum.all?(results, fn
         {:ok, _} -> true
         _ -> false
       end) do
      {:ok, results |> Enum.map(fn {:ok, block} -> block end)}
    else
      {:error, "some decoding of chunks failed"}
    end
  end

  @spec decode_chunk(binary()) :: {:ok, SszTypes.SignedBeaconBlock.t()} | {:error, binary()}
  defp decode_chunk(chunk) do
    {_size, rest} = P2P.Utils.decode_varint(chunk)

    with {:ok, decompressed} <- Snappy.decompress(rest),
         {:ok, signed_block} <-
           decompressed
           |> Ssz.from_ssz(SszTypes.SignedBeaconBlock) do
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
end
