defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  This module contains utility functions for handling epoch processing
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Mutators
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Utils.Randao
  alias Types.BeaconState
  alias Types.DepositMessage
  alias Types.HistoricalSummary
  alias Types.Validator

  @spec process_sync_committee_updates(BeaconState.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_sync_committee_updates(
        %BeaconState{next_sync_committee: next_sync_committee} = state
      ) do
    next_epoch = Accessors.get_current_epoch(state) + 1

    if rem(next_epoch, ChainSpec.get("EPOCHS_PER_SYNC_COMMITTEE_PERIOD")) == 0 do
      with {:ok, new_next_sync_committee} <- Accessors.get_next_sync_committee(state) do
        {:ok,
         %BeaconState{
           state
           | current_sync_committee: next_sync_committee,
             next_sync_committee: new_next_sync_committee
         }}
      end
    else
      {:ok, state}
    end
  end

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
      |> Aja.Vector.zip_with(balances, fn %Validator{} = validator, balance ->
        if balance + downward_threshold < validator.effective_balance or
             validator.effective_balance + upward_threshold < balance do
          min(balance - rem(balance, effective_balance_increment), max_effective_balance)
          |> then(&%{validator | effective_balance: &1})
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
    randao_mix = Randao.get_randao_mix(randao_mixes, current_epoch)
    new_randao_mixes = Randao.replace_randao_mix(randao_mixes, next_epoch, randao_mix)
    new_state = %BeaconState{state | randao_mixes: new_randao_mixes}
    {:ok, new_state}
  end

  @spec process_slashings(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_slashings(%BeaconState{validators: validators, slashings: slashings} = state) do
    epoch = Accessors.get_current_epoch(state)
    total_balance = Accessors.get_total_active_balance(state)

    proportional_slashing_multiplier = ChainSpec.get("PROPORTIONAL_SLASHING_MULTIPLIER_BELLATRIX")
    epochs_per_slashings_vector = ChainSpec.get("EPOCHS_PER_SLASHINGS_VECTOR")
    increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")

    slashed_sum = Enum.reduce(slashings, 0, &+/2)

    adjusted_total_slashing_balance =
      min(slashed_sum * proportional_slashing_multiplier, total_balance)

    penalty_per_effective_balance_increment =
      div(adjusted_total_slashing_balance, div(total_balance, increment))

    new_state =
      validators
      |> Stream.with_index()
      |> Enum.reduce(state, fn {validator, index}, acc ->
        if validator.slashed and
             epoch + div(epochs_per_slashings_vector, 2) == validator.withdrawable_epoch do
          effective_balance_increments = div(validator.effective_balance, increment)
          penalty = penalty_per_effective_balance_increment * effective_balance_increments

          BeaconState.decrease_balance(acc, index, penalty)
        else
          acc
        end
      end)

    {:ok, new_state}
  end

  @spec process_registry_updates(BeaconState.t()) :: {:ok, BeaconState.t()} | {:error, String.t()}
  def process_registry_updates(%BeaconState{validators: validators} = state) do
    ejection_balance = ChainSpec.get("EJECTION_BALANCE")
    current_epoch = Accessors.get_current_epoch(state)
    activation_exit_epoch = Misc.compute_activation_exit_epoch(current_epoch)

    validators
    |> Enum.with_index()
    |> Enum.reduce_while(state, fn {validator, idx}, state ->
      handle_validator_registry_update(
        state,
        validator,
        idx,
        current_epoch,
        activation_exit_epoch,
        ejection_balance
      )
    end)
    |> then(fn
      %BeaconState{} = state -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end)
  end

  defp handle_validator_registry_update(
         state,
         validator,
         idx,
         current_epoch,
         activation_exit_epoch,
         ejection_balance
       ) do
    cond do
      Predicates.eligible_for_activation_queue?(validator) ->
        updated_validator = %Validator{
          validator
          | activation_eligibility_epoch: current_epoch + 1
        }

        {:cont,
         %BeaconState{
           state
           | validators: Aja.Vector.replace_at!(state.validators, idx, updated_validator)
         }}

      Predicates.active_validator?(validator, current_epoch) &&
          validator.effective_balance <= ejection_balance ->
        case Mutators.initiate_validator_exit(state, validator) do
          {:ok, {state, ejected_validator}} ->
            updated_state = %{
              state
              | validators: Aja.Vector.replace_at!(state.validators, idx, ejected_validator)
            }

            {:cont, updated_state}

          {:error, msg} ->
            {:halt, {:error, msg}}
        end

      Predicates.eligible_for_activation?(state, validator) ->
        updated_validator = %Validator{
          validator
          | activation_epoch: activation_exit_epoch
        }

        updated_state = %BeaconState{
          state
          | validators: Aja.Vector.replace_at!(state.validators, idx, updated_validator)
        }

        {:cont, updated_state}

      true ->
        {:cont, state}
    end
  end

  @spec process_participation_flag_updates(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_participation_flag_updates(state) do
    %BeaconState{current_epoch_participation: current_epoch_participation, validators: validators} =
      state

    new_current_epoch_participation = Aja.Vector.duplicate(0, Aja.Vector.size(validators))

    new_state = %BeaconState{
      state
      | previous_epoch_participation: current_epoch_participation,
        current_epoch_participation: new_current_epoch_participation
    }

    {:ok, new_state}
  end

  @spec process_inactivity_updates(BeaconState.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_inactivity_updates(%BeaconState{} = state) do
    genesis_epoch = Constants.genesis_epoch()

    if Accessors.get_current_epoch(state) == genesis_epoch do
      {:ok, state}
    else
      process_inactivity_scores(state)
    end
  end

  defp process_inactivity_scores(%BeaconState{} = state) do
    timely_target_index = Constants.timely_target_flag_index()
    inactivity_score_bias = ChainSpec.get("INACTIVITY_SCORE_BIAS")
    inactivity_score_recovery_rate = ChainSpec.get("INACTIVITY_SCORE_RECOVERY_RATE")
    previous_epoch = Accessors.get_previous_epoch(state)

    # PERF: this can be inlined and combined with the next pipeline
    {:ok, unslashed_participating_indices} =
      Accessors.get_unslashed_participating_indices(state, timely_target_index, previous_epoch)

    state_in_inactivity_leak? = Predicates.in_inactivity_leak?(state)

    state.inactivity_scores
    |> Stream.zip(state.validators)
    |> Stream.with_index()
    |> Enum.map(fn {{inactivity_score, validator}, index} ->
      if Predicates.eligible_validator?(validator, previous_epoch) do
        inactivity_score
        |> Misc.increase_inactivity_score(
          index,
          unslashed_participating_indices,
          inactivity_score_bias
        )
        |> Misc.decrease_inactivity_score(
          state_in_inactivity_leak?,
          inactivity_score_recovery_rate
        )
      else
        inactivity_score
      end
    end)
    |> then(&{:ok, %{state | inactivity_scores: &1}})
  end

  @spec process_historical_summaries_update(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_historical_summaries_update(%BeaconState{} = state) do
    next_epoch = Accessors.get_current_epoch(state) + 1

    slots_per_historical_root = ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")

    epochs_per_historical_root = div(slots_per_historical_root, ChainSpec.get("SLOTS_PER_EPOCH"))

    if rem(next_epoch, epochs_per_historical_root) == 0 do
      with {:ok, block_summary_root} <-
             Ssz.hash_vector_tree_root_typed(
               state.block_roots,
               slots_per_historical_root,
               Types.Root
             ),
           {:ok, state_summary_root} <-
             Ssz.hash_vector_tree_root_typed(
               state.state_roots,
               slots_per_historical_root,
               Types.Root
             ) do
        historical_summary = %HistoricalSummary{
          block_summary_root: block_summary_root,
          state_summary_root: state_summary_root
        }

        new_state = Map.update!(state, :historical_summaries, &(&1 ++ [historical_summary]))

        {:ok, new_state}
      end
    else
      {:ok, state}
    end
  end

  @spec process_justification_and_finalization(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_justification_and_finalization(state) do
    # Initial FFG checkpoint values have a `0x00` stub for `root`.
    # Skip FFG updates in the first two epochs to avoid corner cases that might result in modifying this stub.
    target_index = Constants.timely_target_flag_index()
    previous_epoch = Accessors.get_previous_epoch(state)
    current_epoch = Accessors.get_current_epoch(state)

    if current_epoch <= Constants.genesis_epoch() + 1 do
      {:ok, state}
    else
      previous_target_balance =
        get_total_participating_balance(state, target_index, previous_epoch)

      current_target_balance = get_total_participating_balance(state, target_index, current_epoch)

      total_active_balance = Accessors.get_total_active_balance(state)

      weigh_justification_and_finalization(
        state,
        total_active_balance,
        previous_target_balance,
        current_target_balance
      )
    end
  end

  # NOTE: epoch must be the current or previous one
  defp get_total_participating_balance(state, flag_index, epoch) do
    epoch_participation =
      if epoch == Accessors.get_current_epoch(state) do
        state.current_epoch_participation
      else
        state.previous_epoch_participation
      end

    state.validators
    |> Aja.Vector.zip_with(epoch_participation, fn v, participation ->
      {not v.slashed and Predicates.active_validator?(v, epoch) and
         Predicates.has_flag(participation, flag_index), v.effective_balance}
    end)
    |> Aja.Vector.filter(&elem(&1, 0))
    |> Aja.Enum.reduce(0, fn {true, balance}, acc -> acc + balance end)
  end

  defp weigh_justification_and_finalization(
         state,
         total_active_balance,
         previous_target_balance,
         current_target_balance
       ) do
    previous_epoch = Accessors.get_previous_epoch(state)
    current_epoch = Accessors.get_current_epoch(state)
    old_previous_justified = state.previous_justified_checkpoint
    old_current_justified = state.current_justified_checkpoint
    previous_is_justified = previous_target_balance * 3 >= total_active_balance * 2
    current_is_justified = current_target_balance * 3 >= total_active_balance * 2

    new_state = update_first_bit(state)

    with {:ok, new_state} <-
           update_epoch_justified(new_state, previous_is_justified, previous_epoch, 1),
         {:ok, new_state} <-
           update_epoch_justified(new_state, current_is_justified, current_epoch, 0) do
      new_state
      |> update_checkpoint_finalization(old_previous_justified, current_epoch, 1..3, 3)
      |> update_checkpoint_finalization(old_previous_justified, current_epoch, 1..2, 2)
      |> update_checkpoint_finalization(old_current_justified, current_epoch, 0..2, 2)
      |> update_checkpoint_finalization(old_current_justified, current_epoch, 0..1, 1)
      |> then(&{:ok, &1})
    end
  end

  defp update_first_bit(state) do
    %BeaconState{
      state
      | previous_justified_checkpoint: state.current_justified_checkpoint,
        justification_bits: BitVector.shift_higher(state.justification_bits, 1)
    }
  end

  defp update_epoch_justified(state, false, _, _), do: {:ok, state}

  defp update_epoch_justified(state, true, epoch, index) do
    with {:ok, block_root} <- Accessors.get_block_root(state, epoch) do
      new_checkpoint = %Types.Checkpoint{epoch: epoch, root: block_root}

      %{
        state
        | current_justified_checkpoint: new_checkpoint,
          justification_bits: BitVector.set(state.justification_bits, index)
      }
      |> then(&{:ok, &1})
    end
  end

  defp update_checkpoint_finalization(
         state,
         old_justified_checkpoint,
         current_epoch,
         range,
         offset
       ) do
    bits_set = BitVector.all?(state.justification_bits, range)

    if bits_set and old_justified_checkpoint.epoch + offset == current_epoch do
      %BeaconState{state | finalized_checkpoint: old_justified_checkpoint}
    else
      state
    end
  end

  @spec process_rewards_and_penalties(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_rewards_and_penalties(%BeaconState{} = state) do
    # No rewards are applied at the end of `GENESIS_EPOCH` because rewards are for work done in the previous epoch
    if Accessors.get_current_epoch(state) == Constants.genesis_epoch() do
      {:ok, state}
    else
      deltas =
        Constants.participation_flag_weights()
        |> Stream.with_index()
        |> Stream.map(fn {weight, index} ->
          BeaconState.get_flag_index_deltas(state, weight, index)
        end)
        |> Stream.concat([BeaconState.get_inactivity_penalty_deltas(state)])
        |> Stream.zip()
        |> Aja.Vector.new()

      state.balances
      |> Aja.Vector.zip_with(deltas, &update_balance/2)
      |> then(&{:ok, %BeaconState{state | balances: &1}})
    end
  end

  defp update_balance(balance, deltas) do
    deltas
    |> Tuple.to_list()
    |> Enum.reduce(balance, fn delta, balance ->
      max(balance + delta, 0)
    end)
  end

  @spec process_pending_deposits(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_pending_deposits(%BeaconState{} = state) do
    available_for_processing =
      state.deposit_balance_to_consume + Accessors.get_activation_exit_churn_limit(state)

    finalized_slot = Misc.compute_start_slot_at_epoch(state.finalized_checkpoint.epoch)

    {state, churn_limit_reached, processed_amount, deposits_to_postpone, last_processed_index} =
      state.pending_deposits
      |> Enum.with_index()
      |> Enum.reduce_while({state, false, 0, [], 0}, fn {deposit, index},
                                                        {state, churn_limit_reached,
                                                         processed_amount, deposits_to_postpone,
                                                         _last_processed_index} ->
        cond do
          # Do not process deposit requests if Eth1 bridge deposits are not yet applied.
          deposit.slot > Constants.genesis_slot() &&
              state.eth1_deposit_index < state.deposit_requests_start_index ->
            {:halt,
             {state, churn_limit_reached, processed_amount, deposits_to_postpone, index - 1}}

          # Check if deposit has been finalized, otherwise, stop processing.
          deposit.slot > finalized_slot ->
            {:halt,
             {state, churn_limit_reached, processed_amount, deposits_to_postpone, index - 1}}

          # Check if number of processed deposits has not reached the limit, otherwise, stop processing.
          index >= ChainSpec.get("MAX_PENDING_DEPOSITS_PER_EPOCH") ->
            {:halt,
             {state, churn_limit_reached, processed_amount, deposits_to_postpone, index - 1}}

          true ->
            handle_pending_deposit(
              deposit,
              state,
              churn_limit_reached,
              processed_amount,
              deposits_to_postpone,
              index,
              available_for_processing
            )
        end
      end)

    deposit_balance_to_consume =
      if churn_limit_reached do
        available_for_processing - processed_amount
      else
        0
      end

    {:ok,
     %BeaconState{
       state
       | pending_deposits:
           Enum.drop(state.pending_deposits, last_processed_index + 1)
           |> Enum.concat(deposits_to_postpone),
         deposit_balance_to_consume: deposit_balance_to_consume
     }}
  end

  defp handle_pending_deposit(
         deposit,
         state,
         churn_limit_reached,
         processed_amount,
         deposits_to_postpone,
         index,
         available_for_processing
       ) do
    far_future_epoch = Constants.far_future_epoch()
    next_epoch = Accessors.get_current_epoch(state)

    {is_validator_exited, is_validator_withdrawn} =
      case Enum.find(state.validators, fn v -> v.pubkey == deposit.pubkey end) do
        %Validator{} = validator ->
          {validator.exit_epoch < far_future_epoch, validator.withdrawable_epoch < next_epoch}

        _ ->
          {false, false}
      end

    cond do
      # Deposited balance will never become active. Increase balance but do not consume churn
      is_validator_withdrawn ->
        {:ok, state} = apply_pending_deposit(state, deposit)

        {:cont, {state, churn_limit_reached, processed_amount, deposits_to_postpone, index}}

      # Validator is exiting, postpone the deposit until after withdrawable epoch
      is_validator_exited ->
        deposits_to_postpone = Enum.concat(deposits_to_postpone, [deposit])

        {:cont, {state, churn_limit_reached, processed_amount, deposits_to_postpone, index}}

      true ->
        # Check if deposit fits in the churn, otherwise, do no more deposit processing in this epoch.
        is_churn_limit_reached =
          processed_amount + deposit.amount > available_for_processing

        if is_churn_limit_reached do
          {:halt, {state, true, processed_amount, deposits_to_postpone, index - 1}}
        else
          # Consume churn and apply deposit.
          processed_amount = processed_amount + deposit.amount
          {:ok, state} = apply_pending_deposit(state, deposit)
          {:cont, {state, false, processed_amount, deposits_to_postpone, index}}
        end
    end
  end

  @spec process_pending_consolidations(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_pending_consolidations(%BeaconState{} = state) do
    next_epoch = Accessors.get_current_epoch(state) + 1

    {next_pending_consolidation, state} =
      state.pending_consolidations
      |> Enum.reduce_while({0, state}, fn pending_consolidation,
                                          {next_pending_consolidation, state} ->
        source_index = pending_consolidation.source_index
        target_index = pending_consolidation.target_index
        source_validator = state.validators |> Aja.Vector.at(source_index)

        cond do
          source_validator.slashed ->
            {:cont, {next_pending_consolidation + 1, state}}

          source_validator.withdrawable_epoch > next_epoch ->
            {:halt, {next_pending_consolidation, state}}

          true ->
            source_effective_balance =
              min(
                Aja.Vector.at(state.balances, source_index),
                source_validator.effective_balance
              )

            updated_state =
              state
              |> BeaconState.decrease_balance(source_index, source_effective_balance)
              |> BeaconState.increase_balance(target_index, source_effective_balance)

            {:cont, {next_pending_consolidation + 1, updated_state}}
        end
      end)

    {:ok,
     %BeaconState{
       state
       | pending_consolidations:
           Enum.drop(state.pending_consolidations, next_pending_consolidation)
     }}
  end

  defp apply_pending_deposit(state, deposit) do
    case Enum.find_index(state.validators, fn validator -> validator.pubkey == deposit.pubkey end) do
      index when is_number(index) ->
        {:ok, BeaconState.increase_balance(state, index, deposit.amount)}

      _ ->
        if DepositMessage.valid_deposit_signature?(
             deposit.pubkey,
             deposit.withdrawal_credentials,
             deposit.amount,
             deposit.signature
           ) do
          Mutators.apply_initial_deposit(
            state,
            deposit.pubkey,
            deposit.withdrawal_credentials,
            deposit.amount
          )
        else
          {:ok, state}
        end
    end
  end
end
