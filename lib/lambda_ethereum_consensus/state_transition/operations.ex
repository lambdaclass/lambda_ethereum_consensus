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
    case verify_attestation_for_process(state, attestation) do
      {:ok, _} ->
        data = attestation.data
        aggregation_bits = attestation.aggregation_bits

        case process_attestation(state, data, aggregation_bits) do
          {:ok, updated_state} -> {:ok, updated_state}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_attestation(state, data, aggregation_bits) do
    with {:ok, participation_flag_indices} <-
           Accessors.get_attestation_participation_flag_indices(
             state,
             data,
             state.slot - data.slot
           ),
         {:ok, attesting_indices} <-
           Accessors.get_attesting_indices(state, data, aggregation_bits) do
      is_current_epoch = data.target.epoch == Accessors.get_current_epoch(state)
      initial_epoch_participation = get_initial_epoch_participation(state, is_current_epoch)

      {proposer_reward_numerator, updated_epoch_participation} =
        update_epoch_participation(
          state,
          attesting_indices,
          initial_epoch_participation,
          participation_flag_indices
        )

      proposer_reward = compute_proposer_reward(proposer_reward_numerator)

      {:ok, bal_updated_state} =
        Mutators.increase_balance(
          state,
          Accessors.get_beacon_proposer_index(state),
          proposer_reward
        )

      updated_state =
        update_state(bal_updated_state, is_current_epoch, updated_epoch_participation)

      {:ok, updated_state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_initial_epoch_participation(state, true), do: state.current_epoch_participation
  defp get_initial_epoch_participation(state, false), do: state.previous_epoch_participation

  defp update_epoch_participation(
         state,
         attesting_indices,
         initial_epoch_participation,
         participation_flag_indices
       ) do
    Enum.reduce(attesting_indices, {0, initial_epoch_participation}, fn index, {acc, ep} ->
      update_participation_for_index(state, index, acc, ep, participation_flag_indices)
    end)
  end

  defp update_participation_for_index(state, index, acc, ep, participation_flag_indices) do
    Enum.reduce_while(
      0..(length(Constants.participation_flag_weights()) - 1),
      {acc, ep},
      fn flag_index, {inner_acc, inner_ep} ->
        if flag_index in participation_flag_indices &&
             not Predicates.has_flag(Enum.at(inner_ep, index), flag_index) do
          updated_ep =
            List.replace_at(inner_ep, index, Misc.add_flag(Enum.at(inner_ep, index), flag_index))

          acc_delta =
            Accessors.get_base_reward(state, index) *
              Enum.at(Constants.participation_flag_weights(), flag_index)

          {:cont, {inner_acc + acc_delta, updated_ep}}
        else
          {:cont, {inner_acc, inner_ep}}
        end
      end
    )
  end

  defp compute_proposer_reward(proposer_reward_numerator) do
    proposer_reward_denominator =
      ((Constants.weight_denominator() - Constants.proposer_weight()) *
         Constants.weight_denominator())
      |> div(Constants.proposer_weight())

    div(proposer_reward_numerator, proposer_reward_denominator)
  end

  defp update_state(state, true, updated_epoch_participation),
    do: %{state | current_epoch_participation: updated_epoch_participation}

  defp update_state(state, false, updated_epoch_participation),
    do: %{state | previous_epoch_participation: updated_epoch_participation}

  def verify_attestation_for_process(state, attestation) do
    data = attestation.data

    beacon_committee = fetch_beacon_committee(state, data)
    indexed_attestation = fetch_indexed_attestation(state, attestation)

    if has_invalid_conditions?(data, state, beacon_committee, indexed_attestation, attestation) do
      {:error, get_error_message(data, state, beacon_committee, indexed_attestation, attestation)}
    else
      {:ok, "Valid"}
    end
  end

  defp has_invalid_conditions?(data, state, beacon_committee, indexed_attestation, attestation) do
    invalid_target_epoch?(data, state) ||
      epoch_mismatch?(data) ||
      invalid_slot_range?(data, state) ||
      exceeds_committee_count?(data, state) ||
      !beacon_committee || !indexed_attestation ||
      mismatched_aggregation_bits_length?(attestation, beacon_committee) ||
      invalid_signature?(state, indexed_attestation)
  end

  defp get_error_message(data, state, beacon_committee, indexed_attestation, attestation) do
    cond do
      invalid_target_epoch?(data, state) ->
        "Invalid target epoch"

      epoch_mismatch?(data) ->
        "Epoch mismatch"

      invalid_slot_range?(data, state) ->
        "Invalid slot range"

      exceeds_committee_count?(data, state) ->
        "Index exceeds committee count"

      !beacon_committee || !indexed_attestation ->
        "Indexing error at beacon committee"

      mismatched_aggregation_bits_length?(attestation, beacon_committee) ->
        "Mismatched aggregation bits length"

      invalid_signature?(state, indexed_attestation) ->
        "Invalid signature"
    end
  end

  defp fetch_beacon_committee(state, data) do
    case Accessors.get_beacon_committee(state, data.slot, data.index) do
      {:ok, committee} -> committee
      {:error, _reason} -> nil
    end
  end

  defp fetch_indexed_attestation(state, attestation) do
    case Accessors.get_indexed_attestation(state, attestation) do
      {:ok, indexed_attestation} -> indexed_attestation
      {:error, _reason} -> nil
    end
  end

  defp invalid_target_epoch?(data, state) do
    data.target.epoch < Accessors.get_previous_epoch(state) ||
      data.target.epoch > Accessors.get_current_epoch(state)
  end

  defp epoch_mismatch?(data) do
    data.target.epoch != Misc.compute_epoch_at_slot(data.slot)
  end

  defp invalid_slot_range?(data, state) do
    state.slot < data.slot + ChainSpec.get("MIN_ATTESTATION_INCLUSION_DELAY") ||
      state.slot > data.slot + ChainSpec.get("SLOTS_PER_EPOCH")
  end

  defp exceeds_committee_count?(data, state) do
    data.index >= Accessors.get_committee_count_per_slot(state, data.target.epoch)
  end

  defp mismatched_aggregation_bits_length?(attestation, beacon_committee) do
    length_of_bitstring(attestation.aggregation_bits) - 1 != length(beacon_committee)
  end

  defp invalid_signature?(state, indexed_attestation) do
    Predicates.is_valid_indexed_attestation(state, indexed_attestation) != {:ok, true}
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
