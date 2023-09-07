defmodule LambdaEthereumConsensus.Engine.RPC do
  @moduledoc """
  RPC wrapper enabling calls to compatible endpoints
  """
  use Tesla
  alias LambdaEthereumConsensus.Engine.JWT

  plug(Tesla.Middleware.JSON)

  @doc """
  Builds a JSON-RPC request and calls the endpoint
  """
  @spec rpc_call(binary, binary, binary, map()) :: {:error, any} | {:ok, Tesla.Env.t()}
  def rpc_call(method, endpoint, version, params) do
    {:ok, token, _claims} = JWT.generate_token()

    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"authorization", "Bearer #{token}"}]}
      ])

    request_body =
      %{
        "jsonrpc" => version,
        "method" => method,
        "params" => params,
        "id" => 1
      }

    post(client, endpoint, request_body)
  end

  @doc """
  Validates content of the endpoints response
  """
  @spec validate_rpc_response(any) :: {:ok, any} | {:error, any}
  def validate_rpc_response(result) do
    if Map.has_key?(result.body, "error") do
      {:error, result.body["error"]["message"]}
    else
      {:ok, result.body["result"]}
    end
  end
end
