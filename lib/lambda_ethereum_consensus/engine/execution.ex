defmodule LambdaEthereumConsensus.Engine.Execution do
  @moduledoc """
  Execution Layer Engine API methods
  """
  alias LambdaEthereumConsensus.RPC

  # Default Execution Layer endpoint
  @execution_engine_endpoint "http://0.0.0.0:8551"

  # Default Execution Layer RPC version
  @execution_engine_rpc_version "2.0"

  @doc """
  Notifies the Execution client of a new payload
  """
  @spec notify_new_payload(SszTypes.ExecutionPayload.t()) :: boolean()
  def notify_new_payload(execution_payload) do
    params = %{"ExecutionPayload" => execution_payload}

    with {:ok, result} <-
           RPC.call(
             "engine_newPayloadV2",
             @execution_engine_endpoint,
             @execution_engine_rpc_version,
             params
           ) do
      case RPC.validate_response(result) do
        {:ok, _result} -> true
        _ -> false
      end
    else
      error -> IO.inspect(error)
    end
  end

  @doc """
  Verifies the validity of the data contained in the new payload and notifies the Execution client of a new payload
  """
  @spec verify_and_notify_new_payload(SszTypes.ExecutionPayload.t()) :: boolean()
  def verify_and_notify_new_payload(execution_payload) do
    # Add verification layer
    notify_new_payload(execution_payload)
  end

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
           RPC.call(
             "engine_exchangeCapabilities",
             @execution_engine_endpoint,
             @execution_engine_rpc_version,
             params
           ) do
      RPC.validate_response(result)
    end
  end
end
