defmodule LambdaEthereumConsensus.Engine.Execution do
  @moduledoc """
  Execution Layer Engine API methods
  """
  alias LambdaEthereumConsensus.Engine.RPC

  # Default Execution Layer endpoint
  @execution_engine_endpoint "http://0.0.0.0:8551"

  # Default Execution Layer RPC version
  @execution_engine_rpc_version "2.0"

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  @spec engine_exchange_capabilities(list) :: {:ok, any} | {:error, any}
  def engine_exchange_capabilities(capabilities) do
    params = %{
      "capabilities" => capabilities
    }

    with {:ok, result} <-
           RPC.rpc_call(
             "engine_exchangeCapabilities",
             @execution_engine_endpoint,
             @execution_engine_rpc_version,
             params
           ) do
      RPC.validate_rpc_response(result)
    end
  end
end
