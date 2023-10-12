defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  This module contains utility functions for handling epoch processing
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState

  @spec process_eth1_data_reset(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_eth1_data_reset(state) do
    next_epoch = Accessors.get_current_epoch(state) + 1
    epochs_per_eth1_voting_period = ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD")

    new_state =
      if rem(next_epoch, epochs_per_eth1_voting_period) == 0 do
        %BeaconState{state | eth1_data_votes: []}
      else
        state
      end

    {:ok, new_state}
  end

  @spec process_randao_mixes_reset(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_randao_mixes_reset(%BeaconState{randao_mixes: randao_mixes} = state) do
    current_epoch = Accessors.get_current_epoch(state)
    next_epoch = current_epoch + 1
    epochs_per_historical_vector = ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")
    random_mix = Accessors.get_randao_mix(state, current_epoch)
    index = rem(next_epoch, epochs_per_historical_vector)
    new_randao_mixes = List.replace_at(randao_mixes, index, random_mix)
    new_state = %BeaconState{state | randao_mixes: new_randao_mixes}
    {:ok, new_state}
  end

  @spec process_inactivity_updates(BeaconState.t()) :: {:ok, BeaconState.t()} | {:error, binary()}
  def process_inactivity_updates(%BeaconState{} = state) do
    genesis_epoch = ChainSpec.get("GENESIS_EPOCH")
    timely_target_index = ChainSpec.get("TIMELY_TARGET_FLAG_INDEX")
    inactivity_score_bias = ChainSpec.get("INACTIVITY_SCORE_BIAS")
    inactivity_score_recovery_rate = ChainSpec.get("INACTIVITY_SCORE_RECOVERY_RATE")

    if Accessors.get_current_epoch(state) == genesis_epoch do
      {:ok, state}
    else
      {:ok, unslashed_participating_indices} =
        Accessors.get_unslashed_participating_indices(
          state,
          timely_target_index,
          Accessors.get_previous_epoch(state)
        )

      state_is_in_inactivity_leak = is_in_inactivity_leak(state)

      updated_eligible_validator_indices =
        get_eligible_validator_indices(state)
        |> Enum.map(fn index ->
          inactivity_score = Enum.at(state.inactivity_scores, index)

          new_inactivity_score =
            increase_inactivity_score(
              inactivity_score,
              index,
              unslashed_participating_indices,
              inactivity_score_bias
            )

          new_inactivity_score =
            decrease_inactivity_score(
              new_inactivity_score,
              state_is_in_inactivity_leak,
              inactivity_score_recovery_rate
            )

          {index, new_inactivity_score}
        end)
        |> Enum.into(%{})

      updated_inactive_scores =
        state.inactivity_scores
        |> Stream.with_index()
        |> Stream.map(fn {inactivity_score, index} ->
          update_inactivity_score(updated_eligible_validator_indices, index, inactivity_score)
        end)
        |> Enum.to_list()

      {:ok, %{state | inactivity_scores: updated_inactive_scores}}
    end
  end

  @spec increase_inactivity_score(SszTypes.uint64(), integer, MapSet.t(), SszTypes.uint64()) ::
          SszTypes.uint64()
  defp increase_inactivity_score(
         inactivity_score,
         index,
         unslashed_participating_indices,
         inactivity_score_bias
       ) do
    if MapSet.member?(unslashed_participating_indices, index) do
      inactivity_score - min(1, inactivity_score)
    else
      inactivity_score + inactivity_score_bias
    end
  end

  @spec decrease_inactivity_score(SszTypes.uint64(), boolean, SszTypes.uint64()) ::
          SszTypes.uint64()
  defp decrease_inactivity_score(
         inactivity_score,
         state_is_in_inactivity_leak,
         inactivity_score_recovery_rate
       ) do
    if state_is_in_inactivity_leak do
      inactivity_score
    else
      inactivity_score - min(inactivity_score_recovery_rate, inactivity_score)
    end
  end

  @spec update_inactivity_score(%{integer => SszTypes.uint64()}, integer, {SszTypes.uint64()}) ::
          SszTypes.uint64()
  defp update_inactivity_score(updated_eligible_validator_indices, index, inactivity_score) do
    case Map.fetch(updated_eligible_validator_indices, index) do
      {:ok, new_eligible_validator_index} -> new_eligible_validator_index
      :error -> inactivity_score
    end
  end

  @spec is_in_inactivity_leak(BeaconState.t()) :: boolean
  def is_in_inactivity_leak(%BeaconState{} = state) do
    min_epochs_to_inactivity_penalty = ChainSpec.get("MIN_EPOCHS_TO_INACTIVITY_PENALTY")

    get_finality_delay(state) > min_epochs_to_inactivity_penalty
  end

  @spec get_finality_delay(BeaconState.t()) :: SszTypes.uint64()
  def get_finality_delay(%BeaconState{} = state) do
    Accessors.get_previous_epoch(state) - state.finalized_checkpoint.epoch
  end

  @spec get_eligible_validator_indices(BeaconState.t()) ::
          {:ok, list(SszType.validator_index())} | {:error, binary()}
  def get_eligible_validator_indices(%BeaconState{validators: validators} = state) do
    previous_epoch = Accessors.get_previous_epoch(state)

    validators
    |> Stream.with_index()
    |> Stream.filter(fn {validator, index} ->
      Predicates.is_active_validator(validator, previous_epoch) ||
        (validator.slashed && previous_epoch + 1 < validator.withdrawable_epoch)
    end)
    |> Stream.map(fn {_validator, index} -> index end)
    |> Enum.to_list()
  end
end
