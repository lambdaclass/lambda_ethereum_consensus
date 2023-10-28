defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  This module contains utility functions for handling epoch processing
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Mutators
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState
  alias SszTypes.Validator

  @spec process_effective_balance_updates(BeaconState.t()) ::
          {:ok, BeaconState.t()}
  def process_effective_balance_updates(
        %BeaconState{validators: validators, balances: balances} = state
      ) do
    effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")
    hysteresis_quotient = ChainSpec.get("HYSTERESIS_QUOTIENT")
    hysteresis_downward_multiplier = ChainSpec.get("HYSTERESIS_DOWNWARD_MULTIPLIER")
    hysteresis_upward_multiplier = ChainSpec.get("HYSTERESIS_UPWARD_MULTIPLIER")
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

    hysteresis_increment = div(effective_balance_increment, hysteresis_quotient)
    downward_threshold = hysteresis_increment * hysteresis_downward_multiplier
    upward_threshold = hysteresis_increment * hysteresis_upward_multiplier

    new_validators =
      validators
      |> Stream.zip(balances)
      |> Enum.map(fn {%Validator{effective_balance: effective_balance} = validator, balance} ->
        if balance + downward_threshold < effective_balance or
             effective_balance + upward_threshold < balance do
          new_effective_balance =
            min(balance - rem(balance, effective_balance_increment), max_effective_balance)

          %{validator | effective_balance: new_effective_balance}
        else
          validator
        end
      end)

    {:ok, %BeaconState{state | validators: new_validators}}
  end

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

  @doc """
  Process total slashing balances updates during epoch processing
  """
  @spec process_slashings_reset(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_slashings_reset(state) do
    next_epoch = Accessors.get_current_epoch(state) + 1
    slashed_exit_length = ChainSpec.get("EPOCHS_PER_SLASHINGS_VECTOR")
    slashed_epoch = rem(next_epoch, slashed_exit_length)

    new_slashings = List.replace_at(state.slashings, slashed_epoch, 0)
    new_state = %{state | slashings: new_slashings}
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

  @spec process_registry_updates(BeaconState.t()) :: {:ok, BeaconState.t()} | {:error, binary()}
  def process_registry_updates(%BeaconState{validators: validators} = state) do
    ejection_balance = ChainSpec.get("EJECTION_BALANCE")
    churn_limit = Accessors.get_validator_churn_limit(state)
    churn_limit_range = 0..(churn_limit - 1)

    validators_list = validators |> Stream.with_index() |> Enum.to_list()

    case activation_eligibility_and_ejections(validators_list, state, ejection_balance) do
      {:ok, {new_state, updated_validators_list}} ->
        {state_with_activated_validators, _} =
          updated_validators_list
          |> Stream.with_index()
          |> Stream.filter(fn {validator, _index} ->
            Predicates.is_eligible_for_activation(state, validator)
          end)
          |> Enum.sort_by(fn {validator, index} ->
            {validator.activation_eligibility_epoch, index}
          end)
          |> Enum.slice(churn_limit_range)
          |> Enum.reduce({new_state, updated_validators_list}, fn {validator, index},
                                                                  {state_acc,
                                                                   updated_validators_list_acc} ->
            updated_validator = %{
              validator
              | activation_epoch:
                  Misc.compute_activation_exit_epoch(Accessors.get_current_epoch(state_acc))
            }

            updated_validators_list =
              List.replace_at(updated_validators_list_acc, index, updated_validator)

            {%{state_acc | validators: updated_validators_list}, updated_validators_list}
          end)

        {:ok, state_with_activated_validators}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec activation_eligibility_and_ejections(Enum.t(), BeaconState.t(), SszTypes.gwei()) ::
          {:ok, {BeaconState.t(), Enum.t()}} | {:error, binary()}
  defp activation_eligibility_and_ejections(validators_list_with_index, state, ejection_balance) do
    validators_list_with_index
    |> Enum.reduce_while({:ok, {state, state.validators}}, fn {validator, index},
                                                              {:ok,
                                                               {state_acc, validators_list_acc}} ->
      updated_validator =
        if Predicates.is_eligible_for_activation_queue(validator) do
          %{
            validator
            | activation_eligibility_epoch: Accessors.get_current_epoch(state_acc) + 1
          }
        else
          validator
        end

      if Predicates.is_active_validator(
           updated_validator,
           Accessors.get_current_epoch(state_acc)
         ) &&
           validator.effective_balance <= ejection_balance do
        initiate_validator_exit(state_acc, index, validators_list_acc, updated_validator)
      else
        updated_validators_list = List.replace_at(validators_list_acc, index, updated_validator)

        {:cont,
         {:ok, {%{state_acc | validators: updated_validators_list}, updated_validators_list}}}
      end
    end)
  end

  @spec initiate_validator_exit(BeaconState.t(), integer, Enum.t(), Validator.t()) ::
          {:cont, {:ok, {BeaconState.t(), Enum.t()}}} | {:halt, {:error, binary()}}
  defp initiate_validator_exit(state_acc, index, validators_list_acc, updated_validator) do
    case Mutators.initiate_validator_exit(
           state_acc,
           index
         ) do
      {:ok, validator_exit} ->
        updated_validators_list =
          List.replace_at(
            validators_list_acc,
            index,
            Map.merge(updated_validator, validator_exit)
          )

        {:cont,
         {:ok, {%{state_acc | validators: updated_validators_list}, updated_validators_list}}}

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  @spec process_participation_flag_updates(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_participation_flag_updates(state) do
    %BeaconState{current_epoch_participation: current_epoch_participation, validators: validators} =
      state

    new_current_epoch_participation = for _ <- validators, do: 0

    new_state = %BeaconState{
      state
      | previous_epoch_participation: current_epoch_participation,
        current_epoch_participation: new_current_epoch_participation
    }

    {:ok, new_state}
  end

  @spec process_inactivity_updates(BeaconState.t()) :: {:ok, BeaconState.t()} | {:error, binary()}
  def process_inactivity_updates(%BeaconState{} = state) do
    genesis_epoch = Constants.genesis_epoch()
    timely_target_index = Constants.timely_target_flag_index()
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

      state_is_in_inactivity_leak = Predicates.is_in_inactivity_leak(state)

      updated_eligible_validator_indices =
        Accessors.get_eligible_validator_indices(state)
        |> Enum.map(fn index ->
          inactivity_score = Enum.at(state.inactivity_scores, index)

          new_inactivity_score =
            Misc.increase_inactivity_score(
              inactivity_score,
              index,
              unslashed_participating_indices,
              inactivity_score_bias
            )
            |> Misc.decrease_inactivity_score(
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
          Misc.update_inactivity_score(
            updated_eligible_validator_indices,
            index,
            inactivity_score
          )
        end)
        |> Enum.to_list()

      {:ok, %{state | inactivity_scores: updated_inactive_scores}}
    end
  end

  @spec process_justification_and_finalization(BeaconState.t()) :: BeaconState.t()
  def process_justification_and_finalization(state) do
    # Initial FFG checkpoint values have a `0x00` stub for `root`.
    # Skip FFG updates in the first two epochs to avoid corner cases that might result in modifying this stub.
    new_state =
      if Accessors.get_current_epoch(state) <= ChainSpec.get("GENESIS_EPOCH") + 1 do
        state
      else
        previous_attestations =
          get_matching_target_attestations(state, Accessors.get_previous_epoch(state))

        current_attestations =
          get_matching_target_attestations(state, Accessors.get_current_epoch(state))

        total_active_balance = get_total_active_balance(state)
        previous_target_balance = get_attestating_balance(state, previous_attestations)
        current_target_balance = get_attesting_balance(state, current_attestations)

        state =
          weigh_justification_and_finalization(
            state,
            total_active_balance,
            previous_target_balance,
            current_target_balance
          )

        state
      end

    {:ok, new_state}
  end

  @spec get_matching_source_attestations(BeaconState.t(), SszTypes.epoch()) ::
          {:ok, list(SszTypes.PendingAttestation.t())} | {:error, String.t()}
  def get_matching_source_attestations(state, epoch) do
    {previous_epoch, current_epoch} = {Accessors.get_previous_epoch(state), Accessors.get_current_epoch(state)}

    if epoch in [previous_epoch, current_epoch] do
      if epoch == current_epoch do
        {:ok, state.current_epoch_attestations}
      else
        {:ok, state.previous_epoch_attestations}
      end
    else
      {:error, "Epoch out of range"}
    end
  end

  @spec get_matching_target_attestations(BeaconState.t(), SszTypes.epoch()) ::
          {:ok, list(SszTypes.PendingAttestation.t())} | {:error, String.t()}
  def get_matching_target_attestations(state, epoch) do
    with {:ok, source_attestations} <-
           get_matching_source_attestations(state, epoch) do
      block_root = get_block_root(state, epoch)

      Enum.filter(source_attestations, fn a ->
        a.data.target.root == block_root
      end)
    end
  end

  @doc """
    Return the combined effective balance of the set of unslashed validators participating in ``attestations``.
    Note: ``get_total_balance`` returns ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
  """
  @spec get_attesting_balance(BeaconState.t(), list(SszTypes.PendingAttestation.t())) :: {:ok}
  def get_attesting_balance(state, attestations) do
    Accessors.get_total_balance(
      state,
      Accessors.get_unslashed_attesting_indices(state, attestations)
    )
  end

  @doc """

  """
  @spec weight_justification_and_finalization(BeaconState.t(), SszTypes.gwei(), SszTypes.gwei(), SszTypes.gwei()) :: {:ok, BeaconState.t()}
  def weigh_justification_and_finalization(state, total_active_balance, previous_epoch_target_balance, current_epoch_target_balance) do

    previous_epoch = Accessors.get_previous_epoch(state)
    current_epoch = Accessors.get_current_epoch(state)
    old_previous_justified_checkpoint = state.previous_justified_checkpoint
    old_current_justified_checkpoint = state.current_justified_checkpoint

    # Process justifications
    state.previous_justified_checkpoint = state.current_justified_checkpoint
    state.justification_bits[1:] = state.justification_bits[:JUSTIFICATION_BITS_LENGTH - 1]
    state.justification_bits[0] = 0b0
    if previous_epoch_target_balance * 3 >= total_active_balance * 2:
        state.current_justified_checkpoint = Checkpoint(epoch=previous_epoch,
                                                        root=get_block_root(state, previous_epoch))
        state.justification_bits[1] = 0b1
    if current_epoch_target_balance * 3 >= total_active_balance * 2:
        state.current_justified_checkpoint = Checkpoint(epoch=current_epoch,
                                                        root=get_block_root(state, current_epoch))
        state.justification_bits[0] = 0b1

    # Process finalizations
    bits = state.justification_bits
    # The 2nd/3rd/4th most recent epochs are justified, the 2nd using the 4th as source
    if all(bits[1:4]) and old_previous_justified_checkpoint.epoch + 3 == current_epoch:
        state.finalized_checkpoint = old_previous_justified_checkpoint
    # The 2nd/3rd most recent epochs are justified, the 2nd using the 3rd as source
    if all(bits[1:3]) and old_previous_justified_checkpoint.epoch + 2 == current_epoch:
        state.finalized_checkpoint = old_previous_justified_checkpoint
    # The 1st/2nd/3rd most recent epochs are justified, the 1st using the 3rd as source
    if all(bits[0:3]) and old_current_justified_checkpoint.epoch + 2 == current_epoch:
        state.finalized_checkpoint = old_current_justified_checkpoint
    # The 1st/2nd most recent epochs are justified, the 1st using the 2nd as source
    if all(bits[0:2]) and old_current_justified_checkpoint.epoch + 1 == current_epoch:
        state.finalized_checkpoint = old_current_justified_checkpoint
  end

end
