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

    request_body =
      %{
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
      {:ok, result.body["result"]}
    end
  end

  @spec encode_binary(binary) :: binary
  def encode_binary(binary) do
    "0x" <> Base.encode16(binary, case: :lower)
  end
end
