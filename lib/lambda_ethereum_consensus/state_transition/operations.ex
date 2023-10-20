defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  State transition Operations related functions
  """

  alias SszTypes.ExecutionPayload
  alias SszTypes.BeaconState
  alias LambdaEthereumConsensus.Engine
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Predicates

  @doc """
  State transition function managing the processing & validation of the `ExecutionPayload`
  """
  @spec process_execution_payload(BeaconState.t(), ExecutionPayload.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_execution_payload(state, payload, execution_valid \\ nil) do
    cond do
      # Verify consistency of the parent hash with respect to the previous execution payload header
      Predicates.is_merge_transition_complete(state) and
          payload.parent_hash != state.latest_execution_payload_header.block_hash ->
        {:error, "Inconsistency in parent hash"}

      # Verify prev_randao
      payload.prev_randao != Accessors.get_randao_mix(state, Accessors.get_current_epoch(state)) ->
        {:error, "Prev_randao verification failed"}

      # Verify timestamp
      payload.timestamp != Misc.compute_timestamp_at_slot(state, state.slot) ->
        {:error, "Timestamp verification failed"}

      # Verify the execution payload is valid if not mocked
      execution_valid == nil and
          Engine.Execution.verify_and_notify_new_payload(payload) != {:ok, true} ->
        {:error, "Invalid execution payload"}

      # If execution_valid is set to false
      execution_valid == false ->
        {:error, "Invalid execution payload"}

      # Cache execution payload header
      true ->
        {:ok,
         %BeaconState{
           state
           | latest_execution_payload_header: %SszTypes.ExecutionPayloadHeader{
               parent_hash: payload.parent_hash,
               fee_recipient: payload.fee_recipient,
               state_root: payload.state_root,
               receipts_root: payload.receipts_root,
               logs_bloom: payload.logs_bloom,
               prev_randao: payload.prev_randao,
               block_number: payload.block_number,
               gas_limit: payload.gas_limit,
               gas_used: payload.gas_used,
               timestamp: payload.timestamp,
               extra_data: payload.extra_data,
               base_fee_per_gas: payload.base_fee_per_gas,
               block_hash: payload.block_hash,
               transactions_root:
                 case Ssz.hash_list_tree_root_typed(
                        payload.transactions,
                        ChainSpec.get("MAX_TRANSACTIONS_PER_PAYLOAD"),
                        SszTypes.Transaction
                      ) do
                   {:ok, hash} -> hash
                   {:error, message} -> {:error, message}
                 end,
               withdrawals_root:
                 case Ssz.hash_list_tree_root(
                        payload.withdrawals,
                        ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD")
                      ) do
                   {:ok, hash} -> hash
                   {:error, message} -> {:error, message}
                 end
             }
         }}
    end
  end
end
