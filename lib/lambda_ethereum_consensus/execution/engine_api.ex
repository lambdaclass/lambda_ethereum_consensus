defmodule LambdaEthereumConsensus.Execution.EngineApi do
  @moduledoc """
  Execution Layer Engine API methods with routing
  """

  alias Types.ExecutionPayload

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  @spec exchange_capabilities() :: {:ok, any} | {:error, any}
  def exchange_capabilities, do: impl().exchange_capabilities()

  @spec new_payload(ExecutionPayload.t(), [list(Types.root())], Types.root()) ::
          {:ok, any} | {:error, any}
  def new_payload(execution_payload, versioned_hashes, parent_beacon_block_root),
    do: impl().new_payload(execution_payload, versioned_hashes, parent_beacon_block_root)

  @spec forkchoice_updated(map, map | any) :: {:ok, any} | {:error, any}
  def forkchoice_updated(forkchoice_state, payload_attributes),
    do: impl().forkchoice_updated(forkchoice_state, payload_attributes)

  defp impl, do: Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)[:implementation]
end
