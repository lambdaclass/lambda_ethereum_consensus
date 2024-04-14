defmodule LambdaEthereumConsensus.P2P.ReqResp do
  @moduledoc """
  Functions for encoding and decoding Req/Resp domain messages.
  """

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.P2P
  alias LambdaEthereumConsensus.SszEx

  defmodule Error do
    @moduledoc """
    Error messages for Req/Resp domain.
    """
    defstruct [:code, :message]
    @type t :: %__MODULE__{code: 1..255, message: binary()}

    defp parse_code(1), do: "InvalidRequest"
    defp parse_code(2), do: "ServerError"
    defp parse_code(3), do: "ResourceUnavailable"
    defp parse_code(n), do: "#{n}"

    def format(%Error{code: code, message: message}) do
      "#{parse_code(code)}: #{message}"
    end

    defimpl String.Chars, for: __MODULE__ do
      def to_string(error), do: Error.format(error)
    end
  end

  ## Encoding

  @type context_bytes :: binary()
  @type encodable :: {any(), SszEx.schema()} | struct()

  @type response_payload ::
          {:ok, {encodable(), context_bytes()}}
          | {:error, Error.t()}

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

  @spec encode_error(Error.t()) :: binary()
  def encode_error(%Error{code: code, message: message}), do: encode_error(code, message)

  @spec encode_error(1..255, binary()) :: binary()
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

  @spec decode_response(binary(), SszEx.schema()) ::
          {:ok, [any()]} | {:error, String.t()} | {:error, Error.t()}
  def decode_response(response_chunk, ssz_schema) do
    with {:ok, chunks} <- split_response(response_chunk) do
      # TODO: handle errors
      chunks
      |> Stream.map(&decode_request(&1, ssz_schema))
      |> Enum.flat_map(fn
        {:ok, block} -> [block]
        {:error, _reason} -> []
      end)
      |> then(fn
        [] -> {:error, "all blocks decoding failed"}
        blocks -> {:ok, blocks}
      end)
    end
  end

  @spec split_response(binary) :: {:ok, [binary()]} | {:error, String.t()} | {:error, Error.t()}
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

      <<error_code>> <> message ->
        decode_error(error_code, message)
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
          | {:error, Error.t()}
  def decode_response_chunk(<<0>> <> chunk, ssz_schema), do: decode_request(chunk, ssz_schema)

  def decode_response_chunk(<<code>> <> message, _), do: decode_error(code, message)

  @spec decode_error(1..255, binary()) :: {:error, String.t()} | {:error, Error.t()}
  defp decode_error(code, encoded_message) do
    with {:ok, error_message} <- decode_error_message(encoded_message) do
      {:error, %Error{code: code, message: error_message}}
    end
  end
end
