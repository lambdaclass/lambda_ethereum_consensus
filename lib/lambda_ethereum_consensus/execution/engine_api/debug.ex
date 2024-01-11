defmodule LambdaEthereumConsensus.Execution.EngineApi.Debug do
  @moduledoc """
  Mock Execution Layer Engine API methods
  """

  @supported_methods ["engine_forkchoiceUpdatedV2", "engine_getPayloadV2","engine_newPayloadV2"]

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
  def new_payload_v1(execution_payload) do
    mock_call("engine_newPayloadV2", [execution_payload])
  end

  @spec forkchoice_updated(map, map) :: {:ok, any} | {:error, any}
  def forkchoice_updated(forkchoice_state, payload_attributes) do
    mock_call("engine_forkchoiceUpdatedV2", [forkchoice_state, payload_attributes])
  end

  # This will be used for logging
  defp mock_call(method, params) do
    config = Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)

    endpoint = Keyword.fetch!(config, :endpoint)
    version = Keyword.fetch!(config, :version)
  end
end
