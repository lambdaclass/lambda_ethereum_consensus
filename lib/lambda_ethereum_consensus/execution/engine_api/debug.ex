defmodule LambdaEthereumConsensus.Execution.EngineApi.Debug do
  @moduledoc """
  Mock Execution Layer Engine API methods
  """

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  @spec exchange_capabilities() :: {:ok, any} | {:error, any}
  def exchange_capabilities do
    {:ok, ["engine_newPayloadV2"]}
  end

  @spec new_payload(Types.ExecutionPayload.t()) ::
          {:ok, any} | {:error, any}
  def new_payload_v1(execution_payload) do
    {:ok, generic_response()}
  end

  @spec forkchoice_updated(map, map) :: {:ok, any} | {:error, any}
  def forkchoice_updated(forkchoice_state, payload_attributes) do
    {:ok, generic_response()}
  end

  defp generic_response do
    %{
      "id": 1,
      "jsonrpc": "2.0",
      "result": %{
        payloadId: nil,
        payloadStatus: %{
          status: "VALID",
          latestValidHash: nil,
          validationError: nil
        }
      },
      error: ""
    }
  end

  # This will be used for logging
  defp mock_call(method, params) do
    config =
      Application.fetch_env!(
        :lambda_ethereum_consensus,
        LambdaEthereumConsensus.Execution.EngineApi
      )

    endpoint = Keyword.fetch!(config, :endpoint)
    version = Keyword.fetch!(config, :version)
  end
end
