defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  This module contains utility functions for handling epoch processing
  """

  alias LambdaEthereumConsensus.StateTransition.{Accessors, Misc, Mutators, Predicates}
  alias LambdaEthereumConsensus.Utils.BitVector
  alias SszTypes.{BeaconState, HistoricalSummary, Validator}

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

    new_state =
      validators
      |> Enum.with_index()
      |> Enum.reduce(state, fn {validator, index}, acc ->
        if validator.slashed and
             epoch + div(epochs_per_slashings_vector, 2) == validator.withdrawable_epoch do
          # increment factored out from penalty numerator to avoid uint64 overflow
          penalty_numerator =
            div(validator.effective_balance, increment) * adjusted_total_slashing_balance

          penalty = div(penalty_numerator, total_balance) * increment

          Mutators.decrease_balance(acc, index, penalty)
        else
          acc
        end
      end)

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

    state_is_in_inactivity_leak = Predicates.is_in_inactivity_leak(state)

    state.validators
    |> Stream.zip(state.inactivity_scores)
    |> Stream.with_index()
    |> Enum.map(fn {{validator, inactivity_score}, index} ->
      if Predicates.is_eligible_validator(validator, previous_epoch) do
        inactivity_score
        |> Misc.increase_inactivity_score(
          index,
          unslashed_participating_indices,
          inactivity_score_bias
        )
        |> Misc.decrease_inactivity_score(
          state_is_in_inactivity_leak,
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

    epochs_per_historical_root =
      div(slots_per_historical_root, ChainSpec.get("SLOTS_PER_EPOCH"))

    if rem(next_epoch, epochs_per_historical_root) == 0 do
      with {:ok, block_summary_root} <-
             Ssz.hash_vector_tree_root_typed(
               state.block_roots,
               slots_per_historical_root,
               SszTypes.Root
             ),
           {:ok, state_summary_root} <-
             Ssz.hash_vector_tree_root_typed(
               state.state_roots,
               slots_per_historical_root,
               SszTypes.Root
             ) do
        historical_summary = %HistoricalSummary{
          block_summary_root: block_summary_root,
          state_summary_root: state_summary_root
        }

        new_state =
          Map.update!(state, :historical_summaries, &(&1 ++ [historical_summary]))

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
    genesis_epoch = Constants.genesis_epoch()
    timely_target_index = Constants.timely_target_flag_index()

    if Accessors.get_current_epoch(state) <= genesis_epoch + 1 do
      {:ok, state}
    else
      with {:ok, previous_indices} <-
             Accessors.get_unslashed_participating_indices(
               state,
               timely_target_index,
               Accessors.get_previous_epoch(state)
             ),
           {:ok, current_indices} <-
             Accessors.get_unslashed_participating_indices(
               state,
               timely_target_index,
               Accessors.get_current_epoch(state)
             ) do
        total_active_balance = Accessors.get_total_active_balance(state)
        previous_target_balance = Accessors.get_total_balance(state, previous_indices)
        current_target_balance = Accessors.get_total_balance(state, current_indices)

        weigh_justification_and_finalization(
          state,
          total_active_balance,
          previous_target_balance,
          current_target_balance
        )
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp weigh_justification_and_finalization(
         state,
         total_active_balance,
         previous_epoch_target_balance,
         current_epoch_target_balance
       ) do
    previous_epoch = Accessors.get_previous_epoch(state)
    current_epoch = Accessors.get_current_epoch(state)
    old_previous_justified_checkpoint = state.previous_justified_checkpoint
    old_current_justified_checkpoint = state.current_justified_checkpoint

    with {:ok, previous_block_root} <- Accessors.get_block_root(state, previous_epoch),
         {:ok, current_block_root} <- Accessors.get_block_root(state, current_epoch) do
      new_state =
        state
        |> update_first_bit()
        |> update_previous_epoch_justified(
          previous_epoch_target_balance * 3 >= total_active_balance * 2,
          previous_epoch,
          previous_block_root
        )
        |> update_current_epoch_justified(
          current_epoch_target_balance * 3 >= total_active_balance * 2,
          current_epoch,
          current_block_root
        )
        |> update_checkpoint_finalization(
          old_previous_justified_checkpoint,
          current_epoch,
          1..3,
          3
        )
        |> update_checkpoint_finalization(
          old_previous_justified_checkpoint,
          current_epoch,
          1..2,
          2
        )
        |> update_checkpoint_finalization(
          old_current_justified_checkpoint,
          current_epoch,
          0..2,
          2
        )
        |> update_checkpoint_finalization(
          old_current_justified_checkpoint,
          current_epoch,
          0..1,
          1
        )

      {:ok, new_state}
    end
  end

  defp update_first_bit(state) do
    bits =
      state.justification_bits
      |> BitVector.new(4)
      |> BitVector.shift_higher(1)
      |> to_byte()

    %BeaconState{
      state
      | previous_justified_checkpoint: state.current_justified_checkpoint,
        justification_bits: bits
    }
  end

  defp update_previous_epoch_justified(state, true, previous_epoch, previous_block_root) do
    new_checkpoint = %SszTypes.Checkpoint{
      epoch: previous_epoch,
      root: previous_block_root
    }

    bits =
      state.justification_bits
      |> BitVector.new(4)
      |> BitVector.set(1)
      |> to_byte()

    %BeaconState{
      state
      | current_justified_checkpoint: new_checkpoint,
        justification_bits: bits
    }
  end

  defp update_previous_epoch_justified(state, false, _previous_epoch, _previous_block_root) do
    state
  end

  defp update_current_epoch_justified(state, true, current_epoch, current_block_root) do
    new_checkpoint = %SszTypes.Checkpoint{
      epoch: current_epoch,
      root: current_block_root
    }

    bits =
      state.justification_bits
      |> BitVector.new(4)
      |> BitVector.set(0)
      |> to_byte()

    %BeaconState{
      state
      | current_justified_checkpoint: new_checkpoint,
        justification_bits: bits
    }
  end

  defp update_current_epoch_justified(state, false, _current_epoch, _current_block_root) do
    state
  end

  defp update_checkpoint_finalization(
         state,
         old_justified_checkpoint,
         current_epoch,
         range,
         offset
       ) do
    bits_set =
      state.justification_bits
      |> BitVector.new(4)
      |> BitVector.all?(range)

    if bits_set && old_justified_checkpoint.epoch + offset == current_epoch do
      %BeaconState{state | finalized_checkpoint: old_justified_checkpoint}
    else
      state
    end
  end

  def to_byte(bit_vector) do
    <<0::size(4), bit_vector::bits-size(4)>>
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

      state.balances
      |> Stream.zip(deltas)
      |> Enum.map(&update_balance/1)
      |> then(&{:ok, %{state | balances: &1}})
    end
  end

  defp update_balance({balance, deltas}) do
    deltas
    |> Tuple.to_list()
    |> Enum.reduce(balance, fn {reward, penalty}, balance ->
      max(balance + reward - penalty, 0)
    end)
  end
end
