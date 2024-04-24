defmodule LambdaEthereumConsensus.Execution.RPC do
  @moduledoc false

  use Tesla

  plug(Tesla.Middleware.JSON)

  @spec rpc_call(binary, binary, binary, binary, list) :: {:error, any} | {:ok, Tesla.Env.t()}
  def rpc_call(endpoint, jwt, version, method, params) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"authorization", "Bearer #{jwt}"}]}
      ])

    request_body = %{
      "jsonrpc" => version,
      "method" => method,
      "params" => params,
      "id" => 1
    }

    with {:ok, result} <- post(client, endpoint, request_body) do
      result |> validate_rpc_response()
    end
  end

  @spec validate_rpc_response(any) :: {:ok, any} | {:error, any}
  defp validate_rpc_response(result) do
    if Map.has_key?(result.body, "error") do
      {:error, result.body["error"]["message"]}
    else
      {:ok, result.body["result"] |> normalize_response()}
    end
  end

  def normalize(nil), do: nil

  def normalize(payload) when is_struct(payload) do
    normalize(Map.from_struct(payload))
  end

  def normalize(payload) when is_map(payload) do
    Enum.reduce(payload, %{}, fn {k, v}, acc ->
      Map.put(acc, to_camel_case(k), normalize(v))
    end)
  end

  def normalize(payload) when is_list(payload) do
    Enum.map(payload, &normalize/1)
  end

  def normalize(payload) when is_binary(payload) do
    encode_binary(payload)
  end

  def normalize(payload) when is_integer(payload) do
    payload |> encode_integer()
  end

  def normalize_response(response) when is_map(response) do
    Enum.reduce(response, %{}, fn {k, v}, acc ->
      Map.put(acc, Recase.to_snake(k), v)
    end)
  end

  def normalize_response(response) when is_list(response) do
    Enum.map(response, &normalize_response/1)
  end

  def normalize_response(response) do
    response
  end

  @spec encode_binary(binary) :: binary
  def encode_binary(binary) do
    "0x" <> Base.encode16(binary, case: :lower)
  end

  def encode_integer(integer) do
    "0x" <> (Integer.to_string(integer, 16) |> String.downcase())
  end

  def decode_binary("0x" <> binary) do
    Base.decode16!(binary, case: :lower)
  end

  def decode_integer("0x" <> integer) do
    {number, ""} = Integer.parse(integer, 16)
    number
  end

  defp to_camel_case(key) when is_atom(key) do
    Atom.to_string(key) |> to_camel_case()
  end

  defp to_camel_case(key) when is_binary(key) do
    key
    |> Recase.to_camel()
  end
end
