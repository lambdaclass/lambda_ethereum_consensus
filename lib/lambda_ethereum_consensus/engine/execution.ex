defmodule LambdaEthereumConsensus.Engine.Execution do
  alias LambdaEthereumConsensus.RPC

  # Default Execution Layer endpoint
  @execution_engine_endpoint "http://0.0.0.0:8551"

  # Default Execution Layer RPC version
  @execution_engine_rpc_version "2.0"

  @spec engine_exchange_capabilities(map) :: {:error, any} | {:ok, any}
  def engine_exchange_capabilities(params \\ %{"capabilities" => []}) do
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

  @spec engine_get_payload_v2(map) :: {:error, any} | {:ok, any}
  def engine_get_payload_v2(params \\ %{"payloadId" => "0000000000000000"}) do
    case RPC.call(
           "engine_getPayloadV2",
           @execution_engine_endpoint,
           @execution_engine_rpc_version,
           params
         ) do
      {:ok, result} -> RPC.validate_response(result)
      {:error, error} -> {:error, error}
    end
  end
end
