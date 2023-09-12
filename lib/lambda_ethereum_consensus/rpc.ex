defmodule LambdaEthereumConsensus.RPC do
  @moduledoc """
  RPC wrapper enabling calls to compatible endpoints
  """

  alias LambdaEthereumConsensus.JWT
  use Tesla

  plug(Tesla.Middleware.JSON)

  @doc """
  Builds and calls provided endpoint
  """
  @spec call(binary, binary, binary, map()) :: {:error, any} | {:ok, Tesla.Env.t()}
  def call(method, endpoint, version, params) do
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
  @spec validate_response(any) :: {:ok, any} | {:error, any}
  def validate_response(result) do
    if Map.has_key?(result.body, "error") do
      {:error, result.body["error"]["message"]}
    else
      {:ok, result.body["result"]}
    end
  end
end
