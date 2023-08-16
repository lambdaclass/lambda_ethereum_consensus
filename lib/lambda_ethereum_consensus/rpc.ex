defmodule LambdaEthereumConsensus.RPC do
  alias LambdaEthereumConsensus.JWT
  use Tesla

  plug(Tesla.Middleware.JSON)

  @spec call(binary, binary, binary, map()) :: {:error, any} | {:ok, Tesla.Env.t()}
  def call(method, endpoint, version, params) do
    validate_params(params)

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

  @spec validate_response(atom | %{:body => map, optional(any) => any}) ::
          {:error, any} | {:ok, any}
  def validate_response(result) do
    if Map.has_key?(result.body, "error") do
      {:error, result.body["error"]["message"]}
    else
      {:ok, result.body["result"]}
    end
  end

  defp validate_params(params) do
    if !is_map(params) do
      {:error, "Invalid params"}
    end
  end
end
