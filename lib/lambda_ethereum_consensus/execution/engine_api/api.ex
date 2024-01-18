defmodule LambdaEthereumConsensus.Execution.EngineApi.Api do
  @moduledoc """
  Execution Layer Engine API methods
  """

  alias LambdaEthereumConsensus.Execution.Auth
  alias LambdaEthereumConsensus.Execution.RPC

  @supported_methods ["engine_newPayloadV2"]

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  @spec exchange_capabilities() :: {:ok, any} | {:error, any}
  def exchange_capabilities do
    call("engine_exchangeCapabilities", [@supported_methods])
  end

  @spec new_payload(Types.ExecutionPayload.t()) ::
          {:ok, any} | {:error, any}
  def new_payload(execution_payload) do
    call("engine_newPayloadV2", [RPC.normalize(execution_payload)])
  end

  @spec forkchoice_updated(map, map | any) :: {:ok, any} | {:error, any}
  def forkchoice_updated(forkchoice_state, payload_attributes) do
    call("engine_forkchoiceUpdatedV2", [
      RPC.normalize(forkchoice_state),
      RPC.normalize(payload_attributes)
    ])
  end

  defp call(method, params) do
    config =
      Application.fetch_env!(
        :lambda_ethereum_consensus,
        LambdaEthereumConsensus.Execution.EngineApi
      )

    endpoint = Keyword.fetch!(config, :endpoint)
    version = Keyword.fetch!(config, :version)
    jwt_secret = Keyword.fetch!(config, :jwt_secret)

    {:ok, jwt, _} = Auth.generate_token(jwt_secret)
    RPC.rpc_call(endpoint, jwt, version, method, params)
  end
end
