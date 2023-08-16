defmodule LambdaEthereumConsensus.Engine.Execution do
  alias LambdaEthereumConsensus.RPC

  # Default Execution Layer endpoint
  @execution_engine_endpoint "http://0.0.0.0:8551"

  # Default Execution Layer RPC version
  @execution_engine_rpc_version "2.0"

  @spec engine_exchange_capabilities(list) :: {:ok, any} | {:error, any}
  def engine_exchange_capabilities(capabilities) do
    params = %{
      "capabilities" => capabilities
    }

    case RPC.call(
           "engine_exchangeCapabilities",
           @execution_engine_endpoint,
           @execution_engine_rpc_version,
           params
         ) do
      {:ok, result} -> RPC.validate_response(result)
      {:error, error} -> {:error, error}
    end
  end
end
