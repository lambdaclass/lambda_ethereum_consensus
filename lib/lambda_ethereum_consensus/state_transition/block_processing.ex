defmodule LambdaEthereumConsensus.StateTransition.BlockProcessing do
  @moduledoc """
  Core block processing functions
  """

  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.StateTransition.Accessors

  @doc """
  State_transition function managing the processing & validation of the `ExecutionPayload`
  """
  def process_execution_payload(state, payload) do
    # Verify consistency of the parent hash with respect to the previous execution payload header
    if Predicates.is_merge_transition_complete(state) do
      if payload.parent_hash == state.latest_execution_payload_header.block_hash,
        do: raise("Inconsistency in parent hash")
    end

    # Verify prev_randao
    if payload.prev_randao != Accessors.get_randao_mix(state, Accessors.get_current_epoch(state)),
      do: raise("Prev_randao verification failed")

    # Verify timestamp
    if payload.timestamp != Misc.compute_timestamp_at_slot(state, state.slot),
      do: raise("Timestamp verification failed")

    # Verify the execution payload is valid
    # TODO: Implement notify_new_payload()

    # Cache execution payload header
    # TODO: Update the state and return if
  end
end
