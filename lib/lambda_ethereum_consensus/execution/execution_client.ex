defmodule LambdaEthereumConsensus.Execution.ExecutionClient do
  @moduledoc """
  Execution Layer Engine API methods
  """
  require Logger

  @doc """
  Verifies the validity of the data contained in the new payload and notifies the Execution client of a new payload
  """
  @spec verify_and_notify_new_payload(Types.ExecutionPayload.t()) :: {:ok, any} | {:error, any}
  def verify_and_notify_new_payload(_execution_payload) do
    # TODO: call engine api
    {:ok, true}
  end
end
