defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  This module contains functions for handling state transition
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Mutators
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState
  alias SszTypes.Attestation

  @doc """
  Process total slashing balances updates during epoch processing
  """
  @spec process_attestation(BeaconState.t(), Attestation.t()) 
          :: {:ok, BeaconState.t(), Attestation.t()} | {:error, binary()}
  def process_attestation(state, attestation) do
    data = attestation.data
    cond do
      data.target.epoch not in [Accessors.get_previous_epoch(state), Accessors.get_current_epoch(state)] ->
        {:error, "Incorrect epoch"}
      data.target.epoch != Misc.compute_epoch_at_slot(data.slot) ->
        {:error, "Epoch mismatch"}
      data.slot + ChainSpec.get("MIN_ATTESTATION_INCLUSION_DELAY") > state.slot ->
        {:error, "Inclusion delay not met"}
      data.slot >= Accessors.get_committee_count_per_slot(state, data.target.epoch) ->
        {:error, "Slot exceeds committee count"}
      byte_size(attestation.aggregation_bits) != length(Accessors.get_beacon_committee(state, data.slot, data.index)) ->
        {:error, "Mismatched aggregation bits length"}
    end
    # Participation flag indices 
    {_, participation_flag_indices} = Accessors.get_attestation_participation_flag_indices(state, data, state.slot - data.slot)

    # Verify signature
    state
    |> Accessors.get_indexed_attestation(attestation)
    |> case do
      indexed_attestation when is_map(indexed_attestation) -> 
        if Predicates.is_valid_indexed_attestation(state, indexed_attestation) do
          :ok
        else
          {:error, "Invalid indexed attestation"}
        end
      _ ->
        {:error, "Unable to get indexed attestation"}
    end
    
    # Update epoch participation flags 
    initial_epoch_participation = 
      if data.target.epoch == Accessors.get_current_epoch(state) do
        state.current_epoch_participation
      else
        state.previous_epoch_participation
      end

    attesting_indices = Accessors.get_attesting_indices(state, data, attestation.aggregation_bits)

    {proposer_reward_numerator, _updated_epoch_participation} =
      Enum.reduce(attesting_indices, {0, initial_epoch_participation}, fn index, {acc, ep} ->
        {new_acc, new_ep} = 
          Enum.reduce_while(0..(length(Constants.participation_flag_weights) - 1), {acc, ep}, fn flag_index, {inner_acc, inner_ep} ->
            weight = Enum.at(Constants.participation_flag_weights, flag_index)
            
            if flag_index in participation_flag_indices && 
              not Predicates.has_flag(inner_ep[index], flag_index) do
              updated_ep = Map.put(inner_ep, index, Misc.add_flag(inner_ep[index], flag_index))
              {:cont, {inner_acc + Accessors.get_base_reward(state, index) * weight, updated_ep}}
            else
              {:cont, {inner_acc, inner_ep}}
            end
          end)

        {new_acc, new_ep}
      end)

    # Reward proposer
    proposer_reward_denominator = 
      (Constants.weight_denominator() - Constants.proposer_weight()) * Constants.weight_denominator()
      |> div(Constants.proposer_weight())
    proposer_reward = proposer_reward_numerator |> div(proposer_reward_denominator)
    state = Mutators.increase_balance(state, Accessors.get_beacon_proposer_index(state), proposer_reward)
    {:ok, state, attestation}
  end
end