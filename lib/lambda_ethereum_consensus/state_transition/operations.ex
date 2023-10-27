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
  alias SszTypes

  @doc """
  Process total slashing balances updates during epoch processing
  """
  @spec process_attestation(BeaconState.t(), Attestation.t()) ::
          {:ok, BeaconState.t()} | {:error, binary()}
  def process_attestation(state, attestation) do
    data = attestation.data
    aggregation_bits = attestation.aggregation_bits

    case verify_attestation_for_process(state, attestation) do
      {:ok, _} -> process_attestation(state, data, aggregation_bits)
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_attestation(state, data, aggregation_bits) do
    # Participation flag indices
    with {:ok, participation_flag_indices} <- Accessors.get_attestation_participation_flag_indices(
        state,
        data,
        state.slot - data.slot)
       do
      IO.inspect(participation_flag_indices)

      # Update epoch participation flags
      is_current_epoch = data.target.epoch == Accessors.get_current_epoch(state)
      initial_epoch_participation =
        if is_current_epoch do
          state.current_epoch_participation
        else
          state.previous_epoch_participation
        end

      attesting_indices =
        Accessors.get_attesting_indices(state, data, aggregation_bits)

      {proposer_reward_numerator, updated_epoch_participation} =
        Enum.reduce(attesting_indices, {0, initial_epoch_participation}, fn index, {acc, ep} ->
          {new_acc, new_ep} =
            Enum.reduce_while(
              0..(length(Constants.participation_flag_weights()) - 1),
              {acc, ep},
              fn flag_index, {inner_acc, inner_ep} ->
                if flag_index in participation_flag_indices &&
                    not Predicates.has_flag(Enum.at(inner_ep, index), flag_index) do
                  updated_ep =
                    List.replace_at(
                      inner_ep,
                      index,
                      Misc.add_flag(Enum.at(inner_ep, index), flag_index)
                    )
                  acc_delta =
                    Accessors.get_base_reward(state, index) *
                    Enum.at(Constants.participation_flag_weights(), flag_index)
                  {:cont, {inner_acc + acc_delta, updated_ep}}
                else
                  {:cont, {inner_acc, inner_ep}}
                end
              end
            )

          {new_acc, new_ep}
        end)

      # Reward proposer
      proposer_reward_denominator =
        ((Constants.weight_denominator() - Constants.proposer_weight()) *
            Constants.weight_denominator())
        |> div(Constants.proposer_weight())

      proposer_reward = div(proposer_reward_numerator, proposer_reward_denominator)

      {:ok, bal_updated_state} =
        Mutators.increase_balance(
          state,
          Accessors.get_beacon_proposer_index(state),
          proposer_reward
        )

      updated_state =
        if is_current_epoch do
          %{bal_updated_state | current_epoch_participation: updated_epoch_participation}
        else
          %{bal_updated_state | previous_epoch_participation: updated_epoch_participation}
        end

      {:ok, updated_state}
    else
      error -> error
    end
  end

  defp verify_attestation_for_process(state, attestation) do
    data = attestation.data
    beacon_committee = Accessors.get_beacon_committee(state, data.slot, data.index)

    if data.target.epoch < Accessors.get_previous_epoch(state) ||
      data.target.epoch > Accessors.get_current_epoch(state) do
      {:error, "Incorrect target epoch"}
    end
    if data.target.epoch != Misc.compute_epoch_at_slot(data.slot) do
      {:error, "Epoch mismatch"}
    end
    if state.slot < data.slot + ChainSpec.get("MIN_ATTESTATION_INCLUSION_DELAY") ||
      data.slot + ChainSpec.get("SLOTS_PER_EPOCH") < state.slot do
      {:error, "Inclusion delay not met"}
    end
    if data.index >= Accessors.get_committee_count_per_slot(state, data.target.epoch) do
      {:error, "Index exceeds committee count"}
    end
    # SSZ formatted bitlist has extra 1 bit at the end
    if length_of_bitstring(attestation.aggregation_bits) - 1 !=
      length(beacon_committee) do
      {:error, "Mismatched aggregation bits length"}
    end

    # Verify signature
    indexed_attestation = Accessors.get_indexed_attestation(state, attestation)
    if Predicates.is_valid_indexed_attestation(state, indexed_attestation) do
      {:ok, :valid}
    else
      {:error, "Invalid indexed attestation"}
    end
  end

  defp length_of_bitstring(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.reduce("", fn byte, acc ->
      acc <> Integer.to_string(byte, 2)
    end)
    |> String.length()
  end
end
