defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  This module contains utility functions for handling epoch processing
  """

  alias LambdaEthereumConsensus.StateTransition.{Accessors, Misc, Mutators, Predicates}
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Utils.Randao
  alias Types.{BeaconState, HistoricalSummary, Validator}

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
    randao_mix = Randao.get_randao_mix(state, current_epoch)
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

    new_state =
      validators
      |> Stream.with_index()
      |> Enum.reduce(state, fn {validator, index}, acc ->
        if validator.slashed and
             epoch + div(epochs_per_slashings_vector, 2) == validator.withdrawable_epoch do
          # increment factored out from penalty numerator to avoid uint64 overflow
          penalty_numerator =
            div(validator.effective_balance, increment) * adjusted_total_slashing_balance

          penalty = div(penalty_numerator, total_balance) * increment

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
    churn_limit = Accessors.get_validator_churn_limit(state)
    current_epoch = Accessors.get_current_epoch(state)
    activation_exit_epoch = Misc.compute_activation_exit_epoch(current_epoch)

    result =
      validators
      |> Stream.with_index()
      |> Stream.map(fn {v, i} ->
        {{v, i}, Predicates.is_eligible_for_activation_queue(v),
         Predicates.is_active_validator(v, current_epoch) and
           v.effective_balance <= ejection_balance}
      end)
      |> Stream.filter(&(elem(&1, 1) or elem(&1, 2)))
      |> Stream.map(fn
        {{v, i}, true, b} -> {{%{v | activation_eligibility_epoch: current_epoch + 1}, i}, b}
        {{v, i}, false = _is_eligible, b} -> {{v, i}, b}
      end)
      |> Enum.reduce({:ok, state}, fn
        _, {:error, _} = err -> err
        {{v, i}, should_be_ejected}, {:ok, st} -> eject_validator(st, v, i, should_be_ejected)
        {err, _}, _ -> err
      end)

    with {:ok, new_state} <- result do
      new_state.validators
      |> Stream.with_index()
      |> Stream.filter(fn {v, _} -> Predicates.is_eligible_for_activation(state, v) end)
      |> Enum.sort_by(fn {%{activation_eligibility_epoch: ep}, i} -> {ep, i} end)
      |> Enum.slice(0..(churn_limit - 1))
      |> Enum.reduce(new_state.validators, fn {v, i}, acc ->
        %{v | activation_epoch: activation_exit_epoch}
        |> then(&Aja.Vector.replace_at!(acc, i, &1))
      end)
      |> then(&{:ok, %BeaconState{new_state | validators: &1}})
    end
  end

  defp eject_validator(state, validator, index, false) do
    {:ok, %{state | validators: Aja.Vector.replace_at!(state.validators, index, validator)}}
  end

  defp eject_validator(state, validator, index, true) do
    with {:ok, ejected_validator} <- Mutators.initiate_validator_exit(state, validator) do
      {:ok,
       %{state | validators: Aja.Vector.replace_at!(state.validators, index, ejected_validator)}}
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

    state_is_in_inactivity_leak = Predicates.is_in_inactivity_leak(state)

    state.inactivity_scores
    |> Stream.zip(state.validators)
    |> Stream.with_index()
    |> Enum.map(fn {{inactivity_score, validator}, index} ->
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
    target_index = Constants.timely_target_flag_index()
    previous_epoch = Accessors.get_previous_epoch(state)
    current_epoch = Accessors.get_current_epoch(state)

    if current_epoch <= Constants.genesis_epoch() + 1 do
      {:ok, state}
    else
      previous_target_balance =
        get_total_participating_balance(state, target_index, previous_epoch)

      current_target_balance =
        get_total_participating_balance(state, target_index, current_epoch)

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
      {not v.slashed and Predicates.is_active_validator(v, epoch) and
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
    bits =
      state.justification_bits
      |> BitVector.new(4)
      |> BitVector.shift_higher(1)
      |> BitVector.to_bytes()

    %BeaconState{
      state
      | previous_justified_checkpoint: state.current_justified_checkpoint,
        justification_bits: bits
    }
  end

  defp update_epoch_justified(state, false, _, _), do: {:ok, state}

  defp update_epoch_justified(state, true, epoch, index) do
    with {:ok, block_root} <- Accessors.get_block_root(state, epoch) do
      new_checkpoint = %Types.Checkpoint{epoch: epoch, root: block_root}

      bits =
        state.justification_bits
        |> BitVector.new(4)
        |> BitVector.set(index)
        |> BitVector.to_bytes()

      %{state | current_justified_checkpoint: new_checkpoint, justification_bits: bits}
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
    bits_set =
      state.justification_bits
      |> BitVector.new(4)
      |> BitVector.all?(range)

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
end
