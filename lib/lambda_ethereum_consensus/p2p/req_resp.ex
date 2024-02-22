defmodule LambdaEthereumConsensus.P2P.ReqResp do
  @moduledoc """
  Functions for encoding and decoding Req/Resp domain messages.
  """

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.P2P
  alias LambdaEthereumConsensus.SszEx

  ## Encoding

  @type context_bytes :: binary()
  @type encodable :: {any(), SszEx.schema()} | struct()
  @type error_code :: 1..255
  @type error_message :: binary()

  @type response_payload ::
          {:ok, {encodable(), context_bytes()}}
          | {:error, {error_code(), error_message()}}

  @spec encode_response([response_payload()]) :: binary()
  def encode_response(responses) do
    Enum.map_join(responses, fn
      {:ok, {response, context_bytes}} -> encode_ok(response, context_bytes)
      {:error, {code, message}} -> encode_error(code, message)
    end)
  end

  @spec encode_ok(encodable(), context_bytes()) :: binary()
  def encode_ok(response, context_bytes \\ <<>>)

  def encode_ok(%ssz_schema{} = response, context_bytes),
    do: encode(<<0>>, context_bytes, {response, ssz_schema})

  def encode_ok({response, ssz_schema}, context_bytes),
    do: encode(<<0>>, context_bytes, {response, ssz_schema})

  @spec encode_error(error_code(), error_message()) :: binary()
  def encode_error(status_code, error_message),
    do: encode(<<status_code>>, <<>>, {error_message, TypeAliases.error_message()})

  defp encode(result, context_bytes, {response, ssz_schema}) do
    {:ok, ssz_response} = SszEx.encode(response, ssz_schema)
    size_header = byte_size(ssz_response) |> P2P.Utils.encode_varint()
    {:ok, ssz_snappy_response} = Snappy.compress(ssz_response)
    Enum.join([result, context_bytes, size_header, ssz_snappy_response])
  end

  @spec encode_request(encodable()) :: binary()
  def encode_request(%ssz_schema{} = request), do: encode_request({request, ssz_schema})
  def encode_request({request, ssz_schema}), do: encode(<<>>, <<>>, {request, ssz_schema})

  ## Decoding

  @spec decode_response(binary(), SszEx.schema()) :: {:ok, [any()]} | {:error, String.t()}
  def decode_response(response_chunk, ssz_schema) do
    with {:ok, chunks} <- split_response(response_chunk) do
      # TODO: handle errors
      chunks
      |> Enum.map(&decode_request(&1, ssz_schema))
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

      <<error_code>> <> error_message ->
        {:error, {error_code, decode_error_message(error_message)}}
    end
  end

  defp decode_error_message(error_message),
    do: decode_request(error_message, TypeAliases.error_message())

  @doc """
  Decodes a `request` according to an SSZ schema.
  """
  @spec decode_request(binary(), SszEx.schema()) :: {:ok, any()} | {:error, String.t()}
  def decode_request(chunk, ssz_schema) do
    # TODO: limit size
    {_size, rest} = P2P.Utils.decode_varint(chunk)

    with {:ok, decompressed} <- Snappy.decompress(rest),
         {:ok, decoded} <- SszEx.decode(decompressed, ssz_schema) do
      {:ok, decoded}
    end
  end

  @doc """
  Decodes a `response_chunk` (which includes a status code) according to an SSZ schema.
  """
  @spec decode_response_chunk(binary(), SszEx.schema()) ::
          {:ok, any()}
          | {:error, String.t()}
          | {:error, {error_code(), {:ok, error_message()}}}
          | {:error, {error_code(), {:error, String.t()}}}
  def decode_response_chunk(<<0>> <> chunk, ssz_schema), do: decode_request(chunk, ssz_schema)

  def decode_response_chunk(<<code>> <> message, _),
    do: {:error, {code, decode_error_message(message)}}
end
