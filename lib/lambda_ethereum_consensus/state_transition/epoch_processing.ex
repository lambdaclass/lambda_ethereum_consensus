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

    hysteresis_increment = div(effective_balance_increment, hysteresis_quotient)
    downward_threshold = hysteresis_increment * hysteresis_downward_multiplier
    upward_threshold = hysteresis_increment * hysteresis_upward_multiplier

    new_validators =
      validators
      |> Aja.Vector.zip_with(balances, fn %Validator{} = validator, balance ->
        if balance + downward_threshold < validator.effective_balance or
             validator.effective_balance + upward_threshold < balance do
          min(
            balance - rem(balance, effective_balance_increment),
            Validator.get_max_effective_balance(validator)
          )
          |> then(&%{validator | effective_balance: &1})
        else
          validator
        end
      end)

    {:ok, %BeaconState{state | validators: new_validators}}
  end

  @spec process_eth1_data_reset(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_eth1_data_reset(%BeaconState{} = state) do
    next_epoch = Accessors.get_current_epoch(state) + 1
    epochs_per_eth1_voting_period = ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD")

    new_state =
      if rem(next_epoch, epochs_per_eth1_voting_period) == 0 do
        %{state | eth1_data_votes: []}
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
  def process_registry_updates(%BeaconState{} = state) do
    ejection_balance = ChainSpec.get("EJECTION_BALANCE")
    current_epoch = Accessors.get_current_epoch(state)
    activation_exit_epoch = Misc.compute_activation_exit_epoch(current_epoch)
    far_future_epoch = Constants.far_future_epoch()
    min_activation_balance = ChainSpec.get("MIN_ACTIVATION_BALANCE")
    finalized_epoch = state.finalized_checkpoint.epoch

    ctx =
      {current_epoch, ejection_balance, activation_exit_epoch, far_future_epoch,
       min_activation_balance, finalized_epoch}

    # Use Aja.Vector.foldl instead of Enum.with_index + Enum.reduce_while
    # to avoid materializing the vector to a list (~24MB allocation)
    try do
      state.validators
      |> Aja.Vector.with_index()
      |> Aja.Vector.foldl(state, fn {validator, idx}, state ->
        update_registry_for_validator(validator, idx, state, ctx)
      end)
      |> then(&{:ok, &1})
    catch
      {:error, _} = err -> err
    end
  end

  defp update_registry_for_validator(
         validator,
         idx,
         state,
         {current_epoch, ejection_balance, activation_exit_epoch, far_future_epoch,
          min_activation_balance, finalized_epoch}
       ) do
    cond do
      validator.activation_eligibility_epoch == far_future_epoch &&
          validator.effective_balance >= min_activation_balance ->
        updated = %{validator | activation_eligibility_epoch: current_epoch + 1}
        replace_validator(state, idx, updated)

      Predicates.active_validator?(validator, current_epoch) &&
          validator.effective_balance <= ejection_balance ->
        eject_validator(state, idx, validator)

      validator.activation_eligibility_epoch <= finalized_epoch &&
          validator.activation_epoch == far_future_epoch ->
        updated = %{validator | activation_epoch: activation_exit_epoch}
        replace_validator(state, idx, updated)

      true ->
        state
    end
  end

  defp replace_validator(state, idx, updated_validator) do
    %{state | validators: Aja.Vector.replace_at!(state.validators, idx, updated_validator)}
  end

  defp eject_validator(state, idx, validator) do
    case Mutators.initiate_validator_exit(state, validator) do
      {:ok, {state, ejected}} ->
        replace_validator(state, idx, ejected)

      {:error, msg} ->
        throw({:error, msg})
    end
  end

  @spec process_participation_flag_updates(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_participation_flag_updates(%BeaconState{} = state) do
    %BeaconState{current_epoch_participation: current_epoch_participation, validators: validators} =
      state

    new_current_epoch_participation = Aja.Vector.duplicate(0, Aja.Vector.size(validators))

    new_state = %{
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
    state_in_inactivity_leak? = Predicates.in_inactivity_leak?(state)

    # Single-pass: inline the participation check directly instead of building
    # a MapSet of 2.2M entries then doing MapSet.member? lookups.
    # Zip validators, participation flags, and inactivity_scores together.
    participation = state.previous_epoch_participation

    new_scores =
      state.inactivity_scores
      |> Stream.zip(Aja.Vector.to_list(state.validators))
      |> Stream.zip(Aja.Vector.to_list(participation))
      |> Enum.map(fn {{inactivity_score, validator}, part_flags} ->
        if Predicates.eligible_validator?(validator, previous_epoch) do
          # Inline the unslashed participating check:
          # not slashed AND active (already checked by eligible_validator?) AND has target flag
          is_unslashed_participating =
            not validator.slashed and
              Predicates.has_flag(part_flags, timely_target_index)

          inactivity_score =
            if is_unslashed_participating do
              inactivity_score - min(1, inactivity_score)
            else
              inactivity_score + inactivity_score_bias
            end

          if state_in_inactivity_leak? do
            inactivity_score
          else
            inactivity_score - min(inactivity_score_recovery_rate, inactivity_score)
          end
        else
          inactivity_score
        end
      end)

    {:ok, %{state | inactivity_scores: new_scores}}
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

  # Single-pass: zip_with produces integers (0 or balance), foldl sums them.
  # Avoids the tuple creation + filter + reduce pattern (3 passes → 2 passes,
  # no intermediate filtered vector).
  defp get_total_participating_balance(state, flag_index, epoch) do
    epoch_participation =
      if epoch == Accessors.get_current_epoch(state) do
        state.current_epoch_participation
      else
        state.previous_epoch_participation
      end

    state.validators
    |> Aja.Vector.zip_with(epoch_participation, fn v, participation ->
      if not v.slashed and Predicates.active_validator?(v, epoch) and
           Predicates.has_flag(participation, flag_index),
         do: v.effective_balance,
         else: 0
    end)
    |> Aja.Vector.foldl(0, fn balance, acc -> acc + balance end)
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

  defp update_first_bit(%BeaconState{} = state) do
    %{
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
         %BeaconState{} = state,
         old_justified_checkpoint,
         current_epoch,
         range,
         offset
       ) do
    bits_set = BitVector.all?(state.justification_bits, range)

    if bits_set and old_justified_checkpoint.epoch + offset == current_epoch do
      %{state | finalized_checkpoint: old_justified_checkpoint}
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
      previous_epoch = Accessors.get_previous_epoch(state)
      base_reward_per_increment = Accessors.get_base_reward_per_increment(state)
      effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")
      weights = Constants.participation_flag_weights()
      weight_denominator = Constants.weight_denominator()
      in_inactivity_leak? = Predicates.in_inactivity_leak?(state)
      timely_head_flag_index = Constants.timely_head_flag_index()
      timely_target_flag_index = Constants.timely_target_flag_index()

      penalty_denominator =
        ChainSpec.get("INACTIVITY_SCORE_BIAS") *
          ChainSpec.get("INACTIVITY_PENALTY_QUOTIENT_BELLATRIX")

      active_increments =
        div(Accessors.get_total_active_balance(state), effective_balance_increment)

      participation = state.previous_epoch_participation

      # Pass 1: compute participating balances for each flag (single O(V) scan)
      {bal0, bal1, bal2} =
        state.validators
        |> Aja.Vector.zip_with(participation, fn v, p -> {v, p} end)
        |> Aja.Vector.foldl({0, 0, 0}, fn {v, p}, {b0, b1, b2} ->
          if not v.slashed and Predicates.active_validator?(v, previous_epoch) do
            eb = v.effective_balance
            b0 = if Predicates.has_flag(p, 0), do: b0 + eb, else: b0
            b1 = if Predicates.has_flag(p, 1), do: b1 + eb, else: b1
            b2 = if Predicates.has_flag(p, 2), do: b2 + eb, else: b2
            {b0, b1, b2}
          else
            {b0, b1, b2}
          end
        end)

      participating_increments = [
        div(max(effective_balance_increment, bal0), effective_balance_increment),
        div(max(effective_balance_increment, bal1), effective_balance_increment),
        div(max(effective_balance_increment, bal2), effective_balance_increment)
      ]

      ctx =
        {weights, participating_increments, active_increments, effective_balance_increment,
         base_reward_per_increment, weight_denominator, in_inactivity_leak?,
         timely_head_flag_index, timely_target_flag_index, penalty_denominator, previous_epoch}

      # Pass 2: compute all deltas + apply to balances (single O(V) scan)
      new_balances =
        state.validators
        |> Aja.Vector.zip_with(participation, fn v, p -> {v, p} end)
        |> Aja.Vector.zip_with(state.balances, fn {v, p}, bal -> {v, p, bal} end)
        |> Aja.Vector.zip_with(
          Aja.Vector.new(state.inactivity_scores),
          fn {v, p, bal}, iscore -> {v, p, bal, iscore} end
        )
        |> Aja.Vector.map(fn {validator, part_flags, balance, inactivity_score} ->
          compute_and_apply_deltas(validator, part_flags, balance, inactivity_score, ctx)
        end)

      {:ok, %BeaconState{state | balances: new_balances}}
    end
  end

  defp compute_and_apply_deltas(validator, part_flags, balance, inactivity_score, ctx) do
    {weights, pi_list, ai, ebi, brpi, wd, in_leak?, thfi, ttfi, pd, prev_epoch} = ctx

    if not Predicates.eligible_validator?(validator, prev_epoch) do
      balance
    else
      base_reward = div(validator.effective_balance, ebi) * brpi

      # Apply 3 flag deltas with per-delta clamping
      balance =
        weights
        |> Enum.with_index()
        |> Enum.reduce(balance, fn {weight, flag_index}, bal ->
          upi = Enum.at(pi_list, flag_index)
          is_unslashed = not validator.slashed and Predicates.has_flag(part_flags, flag_index)

          delta =
            cond do
              is_unslashed and in_leak? -> 0
              is_unslashed -> div(base_reward * weight * upi, ai * wd)
              flag_index != thfi -> -div(base_reward * weight, wd)
              true -> 0
            end

          max(bal + delta, 0)
        end)

      # Apply inactivity penalty delta with per-delta clamping
      is_target_unslashed = not validator.slashed and Predicates.has_flag(part_flags, ttfi)

      inactivity_delta =
        if not is_target_unslashed do
          -div(validator.effective_balance * inactivity_score, pd)
        else
          0
        end

      max(balance + inactivity_delta, 0)
    end
  end

  @spec process_pending_deposits(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_pending_deposits(%BeaconState{} = state) do
    available_for_processing =
      state.deposit_balance_to_consume + Accessors.get_activation_exit_churn_limit(state)

    finalized_slot = Misc.compute_start_slot_at_epoch(state.finalized_checkpoint.epoch)
    max_pending = ChainSpec.get("MAX_PENDING_DEPOSITS_PER_EPOCH")

    # Pre-build a pubkey→index map for deposit pubkeys with ONE validator scan.
    # At most 16 deposits, so the lookup set and result map are tiny.
    deposit_pubkeys =
      state.pending_deposits
      |> Enum.take(max_pending)
      |> MapSet.new(& &1.pubkey)

    pubkey_to_index = build_deposit_pubkey_index(state.validators, deposit_pubkeys)

    {state, churn_limit_reached, processed_amount, deposits_to_postpone, last_processed_index,
     _pubkey_to_index} =
      state.pending_deposits
      |> Enum.with_index()
      |> Enum.reduce_while(
        {state, false, 0, [], 0, pubkey_to_index},
        fn {deposit, index},
           {state, churn_limit_reached, processed_amount, deposits_to_postpone,
            _last_processed_index, pubkey_to_index} ->
          cond do
            # Do not process deposit requests if Eth1 bridge deposits are not yet applied.
            deposit.slot > Constants.genesis_slot() &&
                state.eth1_deposit_index < state.deposit_requests_start_index ->
              {:halt,
               {state, churn_limit_reached, processed_amount, deposits_to_postpone, index - 1,
                pubkey_to_index}}

            # Check if deposit has been finalized, otherwise, stop processing.
            deposit.slot > finalized_slot ->
              {:halt,
               {state, churn_limit_reached, processed_amount, deposits_to_postpone, index - 1,
                pubkey_to_index}}

            # Check if number of processed deposits has not reached the limit, otherwise, stop processing.
            index >= max_pending ->
              {:halt,
               {state, churn_limit_reached, processed_amount, deposits_to_postpone, index - 1,
                pubkey_to_index}}

            true ->
              handle_pending_deposit(
                deposit,
                state,
                churn_limit_reached,
                processed_amount,
                deposits_to_postpone,
                index,
                available_for_processing,
                pubkey_to_index
              )
          end
        end
      )

    deposit_balance_to_consume =
      if churn_limit_reached do
        available_for_processing - processed_amount
      else
        0
      end

    {:ok,
     %{
       state
       | pending_deposits:
           Enum.drop(state.pending_deposits, last_processed_index + 1)
           |> Enum.concat(deposits_to_postpone),
         deposit_balance_to_consume: deposit_balance_to_consume
     }}
  end

  # Single scan of validators to find indices for a small set of deposit pubkeys
  defp build_deposit_pubkey_index(validators, deposit_pubkeys) do
    if MapSet.size(deposit_pubkeys) == 0 do
      %{}
    else
      validators
      |> Aja.Vector.with_index()
      |> Aja.Vector.foldl(%{}, &match_deposit_pubkey(&1, &2, deposit_pubkeys))
    end
  end

  defp match_deposit_pubkey({validator, idx}, acc, deposit_pubkeys) do
    if MapSet.member?(deposit_pubkeys, validator.pubkey),
      do: Map.put_new(acc, validator.pubkey, idx),
      else: acc
  end

  defp handle_pending_deposit(
         deposit,
         state,
         churn_limit_reached,
         processed_amount,
         deposits_to_postpone,
         index,
         available_for_processing,
         pubkey_to_index
       ) do
    far_future_epoch = Constants.far_future_epoch()
    next_epoch = Accessors.get_current_epoch(state)

    {is_validator_exited, is_validator_withdrawn} =
      case Map.get(pubkey_to_index, deposit.pubkey) do
        nil ->
          {false, false}

        validator_index ->
          validator = Aja.Vector.at!(state.validators, validator_index)
          {validator.exit_epoch < far_future_epoch, validator.withdrawable_epoch < next_epoch}
      end

    cond do
      # Deposited balance will never become active. Increase balance but do not consume churn
      is_validator_withdrawn ->
        {:ok, state, pubkey_to_index} = apply_pending_deposit(state, deposit, pubkey_to_index)

        {:cont,
         {state, churn_limit_reached, processed_amount, deposits_to_postpone, index,
          pubkey_to_index}}

      # Validator is exiting, postpone the deposit until after withdrawable epoch
      is_validator_exited ->
        deposits_to_postpone = Enum.concat(deposits_to_postpone, [deposit])

        {:cont,
         {state, churn_limit_reached, processed_amount, deposits_to_postpone, index,
          pubkey_to_index}}

      true ->
        # Check if deposit fits in the churn, otherwise, do no more deposit processing in this epoch.
        is_churn_limit_reached =
          processed_amount + deposit.amount > available_for_processing

        if is_churn_limit_reached do
          {:halt,
           {state, true, processed_amount, deposits_to_postpone, index - 1, pubkey_to_index}}
        else
          # Consume churn and apply deposit.
          processed_amount = processed_amount + deposit.amount
          {:ok, state, pubkey_to_index} = apply_pending_deposit(state, deposit, pubkey_to_index)

          {:cont, {state, false, processed_amount, deposits_to_postpone, index, pubkey_to_index}}
        end
    end
  end

  @doc """
  Shift out the first epoch's proposer indices and append new ones for the
  furthest lookahead epoch.
  Spec: process_proposer_lookahead (Fulu, EIP-7917)
  """
  @spec process_proposer_lookahead(BeaconState.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_proposer_lookahead(%BeaconState{} = state) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    # Shift out the first epoch's worth of proposers
    shifted = Enum.drop(state.proposer_lookahead, slots_per_epoch)
    # Compute new proposers for the furthest lookahead epoch
    next_epoch = Accessors.get_current_epoch(state) + ChainSpec.get("MIN_SEED_LOOKAHEAD") + 1

    with {:ok, new_proposers} <- Accessors.get_beacon_proposer_indices(state, next_epoch) do
      {:ok, %BeaconState{state | proposer_lookahead: shifted ++ new_proposers}}
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
     %{
       state
       | pending_consolidations:
           Enum.drop(state.pending_consolidations, next_pending_consolidation)
     }}
  end

  defp apply_pending_deposit(state, deposit, pubkey_to_index) do
    index = Map.get(pubkey_to_index, deposit.pubkey)

    current_validator? = is_number(index)

    valid_signature? =
      current_validator? ||
        DepositMessage.valid_deposit_signature?(
          deposit.pubkey,
          deposit.withdrawal_credentials,
          deposit.amount,
          deposit.signature
        )

    cond do
      current_validator? ->
        {:ok, BeaconState.increase_balance(state, index, deposit.amount), pubkey_to_index}

      !current_validator? && valid_signature? ->
        {:ok, new_state} =
          Mutators.add_validator_to_registry(
            state,
            deposit.pubkey,
            deposit.withdrawal_credentials,
            deposit.amount
          )

        # Update map so subsequent deposits for this pubkey find the new validator
        new_index = Aja.Vector.size(state.validators)
        {:ok, new_state, Map.put(pubkey_to_index, deposit.pubkey, new_index)}

      true ->
        # Neither a validator nor have a valid signature, we do not apply the deposit
        {:ok, state, pubkey_to_index}
    end
  end
end
