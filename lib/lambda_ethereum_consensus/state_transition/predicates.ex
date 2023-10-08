defmodule LambdaEthereumConsensus.StateTransition.Predicates do
  @moduledoc """
  Range of Predicates used during state transition
  """

  @doc """
  Checks if state is pre or post merge
  """
  @spec is_merge_transition_complete(SszTypes.BeaconState) :: boolean()
  def is_merge_transition_complete(state) do
    state.latest_execution_payload_header != SszTypes.ExecutionPayloadHeader
  end
end
