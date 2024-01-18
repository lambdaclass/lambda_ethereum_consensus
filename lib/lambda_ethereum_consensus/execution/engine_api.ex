defmodule LambdaEthereumConsensus.Execution.EngineApi do
  @moduledoc """
  Execution Layer Engine API methods with routing
  """

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  @spec exchange_capabilities() :: {:ok, any} | {:error, any}
  def exchange_capabilities, do: impl().exchange_capabilities()

  @spec new_payload(Types.ExecutionPayload.t()) ::
          {:ok, any} | {:error, any}
  def new_payload(execution_payload), do: impl().new_payload(execution_payload)

  @spec forkchoice_updated(map, map | any) :: {:ok, any} | {:error, any}
  def forkchoice_updated(forkchoice_state, payload_attributes),
    do: impl().forkchoice_updated(forkchoice_state, payload_attributes)

  defp impl,
    do:
      Application.get_env(
        __MODULE__,
        :implementation,
        LambdaEthereumConsensus.Execution.EngineApi.Api
      )
end
