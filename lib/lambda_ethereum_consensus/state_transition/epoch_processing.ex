defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  This module contains utility functions for handling epoch processing
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Mutators
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState
  alias SszTypes.HistoricalSummary
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

  @spec process_historical_summaries_update(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_historical_summaries_update(state) do
    next_epoch = Accessors.get_current_epoch(state) + 1

    new_state =
      if rem(
           next_epoch,
           div(ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT"), ChainSpec.get("SLOTS_PER_EPOCH"))
         ) == 0 do
        historical_summary = %HistoricalSummary{
          block_summary_root:
            case Ssz.hash_list_tree_root_typed(
                   state.block_roots,
                   ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT"),
                   SszTypes.Root
                 ) do
              {:ok, hash} -> hash
              err -> {:error, err}
            end,
          state_summary_root:
            case Ssz.hash_list_tree_root_typed(
                   state.state_roots,
                   ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT"),
                   SszTypes.Root
                 ) do
              {:ok, hash} -> hash
              err -> {:error, err}
            end
        }

        %BeaconState{
          state
          | historical_summaries: state.historical_summaries ++ [historical_summary]
        }
      else
        state
      end

    {:ok, new_state}
  end
end
