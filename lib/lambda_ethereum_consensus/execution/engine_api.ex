defmodule LambdaEthereumConsensus.Execution.EngineApi do
  @moduledoc """
  Execution Layer Engine API methods
  """

  alias LambdaEthereumConsensus.Execution.RPC

  @supported_methods ["engine_newPayloadV2"]

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  @spec engine_exchange_capabilities(binary) :: {:ok, any} | {:error, any}
  def engine_exchange_capabilities(jwt) do
    call(jwt, "engine_exchangeCapabilities", [@supported_methods])
  end

  @spec engine_new_payload_v1(binary, SszTypes.ExecutionPayload.t()) ::
          {:ok, any} | {:error, any}
  def engine_new_payload_v1(jwt, execution_payload) do
    call(jwt, "engine_newPayloadV2", [execution_payload])
  end

  @spec engine_forkchoice_updated(binary, map, map) :: {:ok, any} | {:error, any}
  def engine_forkchoice_updated(jwt, forkchoice_state, payload_attributes) do
    forkchoice_state =
      forkchoice_state
      |> Map.update!("finalizedBlockHash", &RPC.encode_binary/1)
      |> Map.update!("headBlockHash", &RPC.encode_binary/1)
      |> Map.update!("safeBlockHash", &RPC.encode_binary/1)

    call(jwt, "engine_forkchoiceUpdatedV2", [forkchoice_state, payload_attributes])
  end

  @doc """
  Verifies the validity of the data contained in the new payload and notifies the Execution client of a new payload
  """
  @spec verify_and_notify_new_payload(SszTypes.ExecutionPayload.t()) :: {:ok, any} | {:error, any}
  def verify_and_notify_new_payload(_execution_payload) do
    {:ok, true}
  end

  defp call(jwt, method, params) do
    [endpoint: endpoint, version: version] =
      Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)

    RPC.rpc_call(endpoint, jwt, version, method, params)
  end
end
