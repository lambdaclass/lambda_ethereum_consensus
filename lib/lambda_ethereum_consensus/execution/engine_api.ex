defmodule LambdaEthereumConsensus.Execution.EngineApi do
  @moduledoc """
  Execution Layer Engine API methods with routing
  """
  @behaviour LambdaEthereumConsensus.Execution.EngineApi.Behaviour

  def exchange_capabilities, do: impl().exchange_capabilities()

  def new_payload(execution_payload, versioned_hashes, parent_beacon_block_root),
    do: impl().new_payload(execution_payload, versioned_hashes, parent_beacon_block_root)

  def get_payload(payload_id), do: impl().get_payload(payload_id)

  def forkchoice_updated(forkchoice_state, payload_attributes),
    do: impl().forkchoice_updated(forkchoice_state, payload_attributes)

  def get_block_header(block_id), do: impl().get_block_header(block_id)

  def get_deposit_logs(block_number_range), do: impl().get_deposit_logs(block_number_range)

  defp impl, do: Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)[:implementation]
end
