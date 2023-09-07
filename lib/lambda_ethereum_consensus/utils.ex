defmodule LambdaEthereumConsensus.Utils do
  @moduledoc """
  Set of utility functions used throughout the project
  """

  use Tesla
  alias LambdaEthereumConsensus.JWT

  plug(Tesla.Middleware.JSON)

  @doc """
  Syncs the node using an inputed checkpoint
  """
  def sync_from_checkpoint(url) do
    client =
      Tesla.client([
        {Tesla.Middleware.Headers, [{"Accept", "application/octet-stream"}]}
      ])

    case get_call(url, client) do
      {:ok, response} ->
        case Ssz.from_ssz(response.body, SszTypes.BeaconState) do
          {:ok, struct} ->
            IO.inspect(struct)

          _ ->
            IO.puts("There has been an error syncing from checkpoint.")
        end

      _ ->
        IO.puts("Invalid checkpoint sync url.")
    end
  end

  @doc """
  Builds a GET request and calls the endpoint
  """
  @spec get_call(binary, Tesla.Client.t()) :: {:error, any} | {:ok, Tesla.Env.t()}
  def get_call(endpoint, client) do
    get(client, endpoint)
  end

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
