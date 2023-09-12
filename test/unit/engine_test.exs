defmodule Unit.EngineTest do
  alias LambdaEthereumConsensus.RPC
  alias LambdaEthereumConsensus.Engine
  use ExUnit.Case
  doctest Engine

  # Default Execution Layer endpoint
  @execution_engine_endpoint "http://0.0.0.0:8551"

  # Default Execution Layer RPC version
  @execution_engine_rpc_version "2.0"

  test "Call engine_exchangeCapabilities" do
    {:ok, result} =
      RPC.call(
        "engine_exchangeCapabilities",
        @execution_engine_endpoint,
        @execution_engine_rpc_version,
        %{"engine_exchangeCapabilities" => []}
      )

    {:ok, _result} = RPC.validate_response(result)
  end
end
