defmodule LambdaEthereumConsensus.P2P.ReqResp do
  @moduledoc """
  Functions for encoding and decoding Req/Resp domain messages.
  """

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.P2P
  alias LambdaEthereumConsensus.SszEx
  alias Types.SignedBeaconBlock

  ## Encoding

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

  @spec encode_ok(encodable(), context_bytes()) :: binary()
  def encode_ok(response, context_bytes \\ <<>>)

  def encode_ok(%ssz_schema{} = response, context_bytes),
    do: encode(0, context_bytes, {response, ssz_schema})

  def encode_ok({response, ssz_schema}, context_bytes),
    do: encode(0, context_bytes, {response, ssz_schema})

  @spec encode_error(error_code(), error_message()) :: binary()
  def encode_error(status_code, error_message),
    do: encode(status_code, <<>>, {error_message, TypeAliases.error_message()})

  defp encode(result, context_bytes, {response, ssz_schema}) do
    {:ok, ssz_response} = SszEx.encode(response, ssz_schema)
    size_header = byte_size(ssz_response) |> P2P.Utils.encode_varint()
    {:ok, ssz_snappy_response} = Snappy.compress(ssz_response)
    Enum.join([<<result>>, context_bytes, size_header, ssz_snappy_response])
  end

  ## Decoding

  @spec decode_response_chunks(binary()) :: {:ok, [SignedBeaconBlock.t()]} | {:error, String.t()}
  def decode_response_chunks(response_chunk) do
    with {:ok, chunks} <- split_response(response_chunk) do
      # TODO: handle errors
      chunks
      |> Enum.map(&decode(&1, SignedBeaconBlock))
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

      error_response ->
        decode_error(error_response)
    end
  end

  defp decode_error(<<error_code>> <> error_message) do
    case decode(error_message, TypeAliases.error_message()) do
      {:ok, message} ->
        {:error, "error code: #{error_code}, with message: #{message}"}

      {:error, _reason} ->
        message = error_message |> Base.encode16()
        {:error, "error code: #{error_code}, with raw message: '#{message}'"}
    end
  end

  @spec decode(binary(), SszEx.schema()) :: {:ok, any()} | {:error, String.t()}
  def decode(chunk, ssz_schema) do
    # TODO: limit size
    {_size, rest} = P2P.Utils.decode_varint(chunk)

    with {:ok, decompressed} <- Snappy.decompress(rest),
         {:ok, decoded} <- SszEx.decode(decompressed, ssz_schema) do
      {:ok, decoded}
    end
  end
end
