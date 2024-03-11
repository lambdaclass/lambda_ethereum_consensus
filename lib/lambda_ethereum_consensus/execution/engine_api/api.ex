defmodule LambdaEthereumConsensus.Execution.EngineApi.Api do
  @moduledoc """
  Execution Layer Engine API methods
  """

  alias LambdaEthereumConsensus.Execution.EngineApi
  alias LambdaEthereumConsensus.Execution.Auth
  alias LambdaEthereumConsensus.Execution.RPC
  alias Types.ExecutionPayload
  alias Types.ExecutionPayloadDeneb

  @supported_methods ["engine_newPayloadV2", "engine_newPayloadV2"]

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  @spec exchange_capabilities() :: {:ok, any} | {:error, any}
  def exchange_capabilities do
    call("engine_exchangeCapabilities", [@supported_methods])
  end

  @spec new_payload(ExecutionPayload.t()) :: {:ok, any} | {:error, any}
  # CAPELLA
  def new_payload(execution_payload) do
    call("engine_newPayloadV2", [RPC.normalize(execution_payload)])
  end

  @spec new_payload(ExecutionPayloadDeneb.t(), [list(Types.root())], Types.root()) ::
          {:ok, any} | {:error, any}
  # DENEB
  def new_payload(execution_payload, versioned_hashes, parent_beacon_block_root) do
    call(
      "engine_newPayloadV3",
      RPC.normalize([execution_payload, versioned_hashes, parent_beacon_block_root])
    )
  end

  @spec forkchoice_updated(map, map | any) :: {:ok, any} | {:error, any}
  def forkchoice_updated(forkchoice_state, payload_attributes) do
    call("engine_forkchoiceUpdatedV2", RPC.normalize([forkchoice_state, payload_attributes]))
  end

  defp call(method, params) do
    config = Application.fetch_env!(:lambda_ethereum_consensus, EngineApi)

    endpoint = Keyword.fetch!(config, :endpoint)
    version = Keyword.fetch!(config, :version)
    jwt_secret = Keyword.fetch!(config, :jwt_secret)

    jwt = Auth.generate_token(jwt_secret)
    RPC.rpc_call(endpoint, jwt, version, method, params)
  end
end
