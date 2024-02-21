defmodule LambdaEthereumConsensus.P2P.ReqResp do
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.P2P
  alias LambdaEthereumConsensus.SszEx
  alias Types.SignedBeaconBlock

  ## ReqResp encoding

  @type context_bytes :: binary()
  @type encodable :: {any(), SszEx.schema()} | struct()
  @type error_code :: 1..255
  @type error_message :: String.t()

  @type response_payload ::
          {:ok, {encodable(), context_bytes()}}
          | {:error, {error_code(), error_message()}}

  @spec encode_response_chunks([response_payload()]) :: binary()
  def encode_response_chunks(responses) do
    Enum.map_join(responses, fn
      {:ok, {response, context_bytes}} -> encode_ok(response, context_bytes)
      {:error, {code, message}} -> encode_error(code, message)
    end)
  end

  @spec encode_ok(encodable(), context_bytes()) ::
          {:ok, binary()} | {:error, String.t()}
  def encode_ok(response, context_bytes \\ <<>>)

  def encode_ok(%ssz_schema{} = response, context_bytes),
    do: encode_chunk(0, context_bytes, {response, ssz_schema})

  def encode_ok({response, ssz_schema}, context_bytes),
    do: encode_chunk(0, context_bytes, {response, ssz_schema})

  @spec encode_error(error_code(), error_message()) :: binary()
  def encode_error(status_code, error_message),
    do: encode_chunk(status_code, <<>>, {error_message, TypeAliases.error_message()})

  defp encode_chunk(result, context_bytes, {response, ssz_schema}) do
    {:ok, ssz_response} = SszEx.encode(response, ssz_schema)
    size_header = byte_size(ssz_response) |> P2P.Utils.encode_varint()
    {:ok, ssz_snappy_response} = Snappy.compress(ssz_response)
    Enum.join([<<result>>, context_bytes, size_header, ssz_snappy_response])
  end

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

  ## Response decoding

  @spec decode_response_chunks(binary()) :: {:ok, [SignedBeaconBlock.t()]} | {:error, String.t()}
  def decode_response_chunks(response_chunk) do
    with {:ok, chunks} <- split_response(response_chunk) do
      # TODO: handle errors
      chunks
      |> Enum.map(&decode_chunk/1)
      |> Enum.map(fn
        {:ok, block} -> block
        {:error, _reason} -> nil
      end)
      |> Enum.filter(&(&1 != nil))
      |> then(fn
        [] -> {:error, "all blocks decoding failed"}
        blocks -> {:ok, blocks}
      end)
    end
  end

  @spec split_response(binary) :: {:ok, [binary()]} | {:error, String.t()}
  def split_response(response_chunk) do
    # TODO: the fork_context should be computed depending on the block's slot
    fork_context = BeaconChain.get_fork_digest()

    case response_chunk do
      <<>> ->
        {:error, "unexpected EOF"}

      # TODO: take into account multiple chunks with intermixed errors
      <<0, ^fork_context::binary-size(4)>> <> rest ->
        chunks = rest |> :binary.split(<<0, fork_context::binary-size(4)>>, [:global])
        {:ok, chunks}

      <<0, wrong_context::binary-size(4)>> <> _ ->
        {:error, "wrong context: #{Base.encode16(wrong_context)}"}

      <<code>> <> message ->
        decode_error_response(code, message)
    end
  end

  defp decode_error_response(error_code, ""), do: {:error, "error code: #{error_code}"}

  defp decode_error_response(error_code, error_message) do
    {_size, rest} = P2P.Utils.decode_varint(error_message)

    case rest |> Snappy.decompress() do
      {:ok, message} ->
        {:error, "error code: #{error_code}, with message: #{message}"}

      {:error, _reason} ->
        message = error_message |> Base.encode16()
        {:error, "error code: #{error_code}, with raw message: '#{message}'"}
    end
  end

  @spec decode_chunk(binary()) :: {:ok, SignedBeaconBlock.t()} | {:error, binary()}
  defp decode_chunk(chunk) do
    {_size, rest} = P2P.Utils.decode_varint(chunk)

    with {:ok, decompressed} <- Snappy.decompress(rest),
         {:ok, signed_block} <- Ssz.from_ssz(decompressed, SignedBeaconBlock) do
      {:ok, signed_block}
    end
  end
end
