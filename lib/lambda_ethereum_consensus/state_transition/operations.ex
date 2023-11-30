defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  This module contains functions for handling state transition
  """

  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.StateTransition.{Accessors, Math, Misc, Mutators, Predicates}
  alias LambdaEthereumConsensus.Utils.BitVector

  alias SszTypes.{
    Attestation,
    BeaconBlock,
    BeaconBlockBody,
    BeaconBlockHeader,
    BeaconState,
    ExecutionPayload,
    SyncAggregate,
    Validator,
    Withdrawal
  }

  @spec process_block_header(BeaconState.t(), BeaconBlock.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_block_header(
        %BeaconState{slot: state_slot, latest_block_header: latest_block_header} = state,
        %BeaconBlock{slot: block_slot, proposer_index: proposer_index, parent_root: parent_root} =
          block
      ) do
    with :ok <- check_slots_match(state_slot, block_slot),
         :ok <-
           check_block_is_newer_than_latest_block_header(block_slot, latest_block_header.slot),
         :ok <- check_proposer_index_is_correct(proposer_index, state),
         :ok <- check_parent_root_match(parent_root, latest_block_header),
         {:ok, state} <- cache_current_block(state, block) do
      # Verify proposer is not slashed
      proposer = state.validators |> Enum.fetch!(proposer_index)

      if proposer.slashed do
        {:error, "proposer is slashed"}
      else
        {:ok, state}
      end
    end
  end

  @spec check_slots_match(SszTypes.slot(), SszTypes.slot()) ::
          :ok | {:error, String.t()}
  defp check_slots_match(state_slot, block_slot) do
    # Verify that the slots match
    if block_slot == state_slot do
      :ok
    else
      {:error, "slots don't match"}
    end
  end

  @spec check_block_is_newer_than_latest_block_header(SszTypes.slot(), SszTypes.slot()) ::
          :ok | {:error, String.t()}
  defp check_block_is_newer_than_latest_block_header(block_slot, latest_block_header_slot) do
    # Verify that the block is newer than latest block header
    if block_slot > latest_block_header_slot do
      :ok
    else
      {:error, "block is not newer than latest block header"}
    end
  end

  @spec check_proposer_index_is_correct(SszTypes.validator_index(), BeaconState.t()) ::
          :ok | {:error, String.t()}
  defp check_proposer_index_is_correct(block_proposer_index, state) do
    # Verify that proposer index is the correct index
    with {:ok, proposer_index} <- Accessors.get_beacon_proposer_index(state) do
      if block_proposer_index == proposer_index do
        :ok
      else
        {:error, "proposer index is incorrect"}
      end
    end
  end

  @spec check_parent_root_match(SszTypes.root(), BeaconBlockHeader.t()) ::
          :ok | {:error, String.t()}
  defp check_parent_root_match(parent_root, latest_block_header) do
    # Verify that the parent matches
    with {:ok, root} <- Ssz.hash_tree_root(latest_block_header) do
      if parent_root == root do
        :ok
      else
        {:error, "parent roots mismatch"}
      end
    end
  end

  @spec cache_current_block(BeaconState.t(), BeaconBlock.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  defp cache_current_block(state, block) do
    # Cache current block as the new latest block
    with {:ok, root} <- Ssz.hash_tree_root(block.body) do
      latest_block_header = %BeaconBlockHeader{
        slot: block.slot,
        proposer_index: block.proposer_index,
        parent_root: block.parent_root,
        state_root: <<0::256>>,
        body_root: root
      }

      {:ok, %BeaconState{state | latest_block_header: latest_block_header}}
    end
  end

  @spec process_sync_aggregate(BeaconState.t(), SyncAggregate.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_sync_aggregate(%BeaconState{} = state, %SyncAggregate{} = aggregate) do
    # Verify sync committee aggregate signature signing over the previous slot block root
    committee_pubkeys = state.current_sync_committee.pubkeys
    sync_committee_bits = parse_sync_committee_bits(aggregate.sync_committee_bits)

    participant_pubkeys =
      committee_pubkeys
      |> Enum.with_index()
      |> Enum.filter(fn {_, index} -> BitVector.set?(sync_committee_bits, index) end)
      |> Enum.map(fn {public_key, _} -> public_key end)

    previous_slot = max(state.slot, 1) - 1
    epoch = Misc.compute_epoch_at_slot(previous_slot)
    domain = Accessors.get_domain(state, Constants.domain_sync_committee(), epoch)

    with {:ok, block_root} <- Accessors.get_block_root_at_slot(state, previous_slot),
         signing_root <- Misc.compute_signing_root(block_root, domain),
         :ok <-
           verify_signature(participant_pubkeys, signing_root, aggregate.sync_committee_signature),
         {:ok, proposer_index} <- Accessors.get_beacon_proposer_index(state) do
      # Compute participant and proposer rewards
      {participant_reward, proposer_reward} = compute_sync_aggregate_rewards(state)

      total_proposer_reward = BitVector.count(sync_committee_bits) * proposer_reward

      # PERF: make Map with committee_index by pubkey, then
      # Enum.map validators -> new balance all in place, without map_reduce
      committee_deltas =
        state.validators
        |> get_sync_committee_indices(committee_pubkeys)
        |> Stream.with_index()
        |> Stream.map(fn {validator_index, committee_index} ->
          if BitVector.set?(sync_committee_bits, committee_index),
            do: {validator_index, participant_reward},
            else: {validator_index, -participant_reward}
        end)
        |> Enum.sort(fn {vi1, _}, {vi2, _} -> vi1 <= vi2 end)

      # Apply participant and proposer rewards
      {new_balances, []} =
        state.balances
        |> Stream.with_index()
        |> Stream.map(&add_proposer_reward(&1, proposer_index, total_proposer_reward))
        |> Enum.map_reduce(committee_deltas, &update_balance/2)

      {:ok, %BeaconState{state | balances: new_balances}}
    end
  end

  defp add_proposer_reward({balance, proposer}, proposer, proposer_reward),
    do: {balance + proposer_reward, proposer}

  defp add_proposer_reward(v, _, _), do: v

  defp update_balance({balance, i}, [{i, delta} | acc]),
    do: update_balance({max(balance + delta, 0), i}, acc)

  defp update_balance({balance, _}, acc), do: {balance, acc}

  defp verify_signature(pubkeys, message, signature) do
    case Bls.eth_fast_aggregate_verify(pubkeys, message, signature) do
      {:ok, true} -> :ok
      _ -> {:error, "Signature verification failed"}
    end
  end

  defp parse_sync_committee_bits(bits) do
    # TODO: Change bitvectors to be in little-endian instead of converting manually
    bitsize = bit_size(bits)
    <<num::integer-size(bitsize)>> = bits
    <<num::integer-little-size(bitsize)>>
  end

  @spec compute_sync_aggregate_rewards(BeaconState.t()) :: {SszTypes.gwei(), SszTypes.gwei()}
  defp compute_sync_aggregate_rewards(state) do
    # Compute participant and proposer rewards
    total_active_balance = Accessors.get_total_active_balance(state)

    effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")
    total_active_increments = total_active_balance |> div(effective_balance_increment)

    numerator = effective_balance_increment * Constants.base_reward_factor()
    denominator = Math.integer_squareroot(total_active_balance)
    base_reward_per_increment = div(numerator, denominator)
    total_base_rewards = base_reward_per_increment * total_active_increments

    max_participant_rewards =
      (total_base_rewards * Constants.sync_reward_weight())
      |> div(Constants.weight_denominator())
      |> div(ChainSpec.get("SLOTS_PER_EPOCH"))

    participant_reward = div(max_participant_rewards, ChainSpec.get("SYNC_COMMITTEE_SIZE"))

    proposer_reward =
      (participant_reward * Constants.proposer_weight())
      |> div(Constants.weight_denominator() - Constants.proposer_weight())

    {participant_reward, proposer_reward}
  end

  @spec get_sync_committee_indices(list(Validator.t()), list(SszTypes.bls_pubkey())) ::
          list(integer)
  defp get_sync_committee_indices(validators, committee_pubkeys) do
    all_pubkeys =
      validators
      |> Stream.map(fn %Validator{pubkey: pubkey} -> pubkey end)
      |> Stream.with_index()
      |> Map.new()

    committee_pubkeys
    |> Enum.map(&Map.fetch!(all_pubkeys, &1))
  end

  @doc """
  State transition function managing the processing & validation of the `ExecutionPayload`
  """
  @spec process_execution_payload(BeaconState.t(), BeaconBlockBody.t(), fun()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_execution_payload(
        state,
        %BeaconBlockBody{execution_payload: payload},
        verify_and_notify_new_payload
      ) do
    cond do
      # Verify consistency of the parent hash with respect to the previous execution payload header
      SszTypes.BeaconState.is_merge_transition_complete(state) and
          payload.parent_hash != state.latest_execution_payload_header.block_hash ->
        {:error, "Inconsistency in parent hash"}

      # Verify prev_randao
      payload.prev_randao != Accessors.get_randao_mix(state, Accessors.get_current_epoch(state)) ->
        {:error, "Prev_randao verification failed"}

      # Verify timestamp
      payload.timestamp != Misc.compute_timestamp_at_slot(state, state.slot) ->
        {:error, "Timestamp verification failed"}

      # Verify the execution payload is valid if not mocked
      verify_and_notify_new_payload.(payload) != {:ok, true} ->
        {:error, "Invalid execution payload"}

      # Cache execution payload header
      true ->
        with {:ok, transactions_root} <-
               Ssz.hash_list_tree_root_typed(
                 payload.transactions,
                 ChainSpec.get("MAX_TRANSACTIONS_PER_PAYLOAD"),
                 SszTypes.Transaction
               ),
             {:ok, withdrawals_root} <-
               Ssz.hash_list_tree_root(
                 payload.withdrawals,
                 ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD")
               ) do
          {:ok,
           %BeaconState{
             state
             | latest_execution_payload_header: %SszTypes.ExecutionPayloadHeader{
                 parent_hash: payload.parent_hash,
                 fee_recipient: payload.fee_recipient,
                 state_root: payload.state_root,
                 receipts_root: payload.receipts_root,
                 logs_bloom: payload.logs_bloom,
                 prev_randao: payload.prev_randao,
                 block_number: payload.block_number,
                 gas_limit: payload.gas_limit,
                 gas_used: payload.gas_used,
                 timestamp: payload.timestamp,
                 extra_data: payload.extra_data,
                 base_fee_per_gas: payload.base_fee_per_gas,
                 block_hash: payload.block_hash,
                 transactions_root: transactions_root,
                 withdrawals_root: withdrawals_root
               }
           }}
        end
    end
  end

  @doc """
  Apply withdrawals to the state.
  """
  @spec process_withdrawals(BeaconState.t(), ExecutionPayload.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_withdrawals(
        %BeaconState{
          validators: validators
        } = state,
        %ExecutionPayload{withdrawals: withdrawals}
      ) do
    expected_withdrawals = get_expected_withdrawals(state)

    with :ok <- check_withdrawals(withdrawals, expected_withdrawals) do
      state
      |> decrease_balances(withdrawals)
      |> update_next_withdrawal_index(withdrawals)
      |> update_next_withdrawal_validator_index(withdrawals, length(validators))
      |> then(&{:ok, &1})
    end
  end

  # Update the next withdrawal index if this block contained withdrawals
  @spec update_next_withdrawal_index(BeaconState.t(), list(Withdrawal.t())) :: BeaconState.t()
  defp update_next_withdrawal_index(state, []), do: state

  defp update_next_withdrawal_index(state, withdrawals) do
    latest_withdrawal = List.last(withdrawals)
    %BeaconState{state | next_withdrawal_index: latest_withdrawal.index + 1}
  end

  @spec update_next_withdrawal_validator_index(BeaconState.t(), list(Withdrawal.t()), integer()) ::
          BeaconState.t()
  defp update_next_withdrawal_validator_index(state, withdrawals, validator_len) do
    next_index =
      if length(withdrawals) == ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD") do
        # Update the next validator index to start the next withdrawal sweep
        latest_withdrawal = List.last(withdrawals)
        latest_withdrawal.validator_index + 1
      else
        # Advance sweep by the max length of the sweep if there was not a full set of withdrawals
        state.next_withdrawal_validator_index +
          ChainSpec.get("MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP")
      end

    next_validator_index = rem(next_index, validator_len)
    %BeaconState{state | next_withdrawal_validator_index: next_validator_index}
  end

  @spec check_withdrawals(list(Withdrawal.t()), list(Withdrawal.t())) ::
          :ok | {:error, String.t()}
  defp check_withdrawals(withdrawals, expected_withdrawals)
       when length(withdrawals) !== length(expected_withdrawals) do
    {:error, "expected withdrawals don't match the state withdrawals in length"}
  end

  defp check_withdrawals(withdrawals, expected_withdrawals) do
    Stream.zip(expected_withdrawals, withdrawals)
    |> Enum.all?(fn {expected_withdrawal, withdrawal} ->
      expected_withdrawal == withdrawal
    end)
    |> then(&if &1, do: :ok, else: {:error, "withdrawal doesn't match expected withdrawal"})
  end

  @spec decrease_balances(BeaconState.t(), list(Withdrawal.t())) :: BeaconState.t()
  defp decrease_balances(state, withdrawals) do
    withdrawals = Enum.sort(withdrawals, &(&1.validator_index <= &2.validator_index))

    state.balances
    |> Stream.with_index()
    |> Enum.map_reduce(withdrawals, &maybe_decrease_balance/2)
    |> then(fn {balances, []} -> %BeaconState{state | balances: balances} end)
  end

  defp maybe_decrease_balance({balance, index}, [
         %Withdrawal{validator_index: index, amount: amount} | remaining
       ]),
       do: {max(balance - amount, 0), remaining}

  defp maybe_decrease_balance({balance, _index}, acc), do: {balance, acc}

  @spec get_expected_withdrawals(BeaconState.t()) :: list(Withdrawal.t())
  defp get_expected_withdrawals(%BeaconState{} = state) do
    # Compute the next batch of withdrawals which should be included in a block.
    epoch = Accessors.get_current_epoch(state)

    max_validators_per_withdrawals_sweep = ChainSpec.get("MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP")
    max_withdrawals_per_payload = ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD")
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

    bound = min(length(state.validators), max_validators_per_withdrawals_sweep)

    Stream.zip([state.validators, state.balances])
    |> Stream.with_index()
    |> Stream.cycle()
    |> Stream.drop(state.next_withdrawal_validator_index)
    |> Stream.take(bound)
    |> Stream.map(fn {{validator, balance}, index} ->
      cond do
        Validator.is_fully_withdrawable_validator(validator, balance, epoch) ->
          {validator, balance, index}

        Validator.is_partially_withdrawable_validator(validator, balance) ->
          {validator, balance - max_effective_balance, index}

        true ->
          nil
      end
    end)
    |> Stream.reject(&is_nil/1)
    |> Stream.with_index()
    |> Stream.map(fn {{validator, balance, validator_index}, index} ->
      %Validator{withdrawal_credentials: withdrawal_credentials} = validator

      <<_::binary-size(12), execution_address::binary>> = withdrawal_credentials

      %Withdrawal{
        index: index + state.next_withdrawal_index,
        validator_index: validator_index,
        address: execution_address,
        amount: balance
      }
    end)
    |> Enum.take(max_withdrawals_per_payload)
  end

  @spec process_proposer_slashing(BeaconState.t(), SszTypes.ProposerSlashing.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_proposer_slashing(state, proposer_slashing) do
    header_1 = proposer_slashing.signed_header_1.message
    header_2 = proposer_slashing.signed_header_2.message
    proposer = Enum.at(state.validators, header_1.proposer_index)

    cond do
      not Predicates.is_indices_available(
        length(state.validators),
        [header_1.proposer_index]
      ) ->
        {:error, "Too high index"}

      not (header_1.slot == header_2.slot) ->
        {:error, "Slots don't match"}

      not (header_1.proposer_index == header_2.proposer_index) ->
        {:error, "Proposer indices don't match"}

      not (header_1 != header_2) ->
        {:error, "Headers are same"}

      not Predicates.is_slashable_validator(proposer, Accessors.get_current_epoch(state)) ->
        {:error, "Proposer is not slashable"}

      true ->
        is_verified =
          [proposer_slashing.signed_header_1, proposer_slashing.signed_header_2]
          |> Enum.all?(&verify_proposer_slashing(&1, state, proposer))

        if is_verified do
          Mutators.slash_validator(state, header_1.proposer_index)
        else
          {:error, "Signed header 1 or 2 signature is not verified"}
        end
    end
  end

  defp verify_proposer_slashing(signed_header, state, proposer) do
    domain =
      Accessors.get_domain(
        state,
        Constants.domain_beacon_proposer(),
        Misc.compute_epoch_at_slot(signed_header.message.slot)
      )

    signing_root =
      Misc.compute_signing_root(signed_header.message, domain)

    bls_verify_proposer_slashing(
      proposer.pubkey,
      signing_root,
      signed_header.signature
    )
  end

  defp bls_verify_proposer_slashing(pubkey, signing_root, signature) do
    verification = Bls.verify(pubkey, signing_root, signature)

    case verification do
      {:ok, bool} ->
        bool

      {:error, _msg} ->
        true
    end
  end

  @spec process_deposit(BeaconState.t(), SszTypes.Deposit.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_deposit(state, deposit) do
    with {:ok, deposit_data_root} <- Ssz.hash_tree_root(deposit.data) do
      if Predicates.is_valid_merkle_branch?(
           deposit_data_root,
           deposit.proof,
           Constants.deposit_contract_tree_depth() + 1,
           state.eth1_deposit_index,
           state.eth1_data.deposit_root
         ) do
        state
        |> Map.put(:eth1_deposit_index, state.eth1_deposit_index + 1)
        |> Mutators.apply_deposit(
          deposit.data.pubkey,
          deposit.data.withdrawal_credentials,
          deposit.data.amount,
          deposit.data.signature
        )
      else
        {:error, "Merkle branch is not valid"}
      end
    end
  end

  @spec process_attester_slashing(BeaconState.t(), SszTypes.AttesterSlashing.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_attester_slashing(state, attester_slashing) do
    attestation_1 = attester_slashing.attestation_1
    attestation_2 = attester_slashing.attestation_2

    cond do
      not Predicates.is_slashable_attestation_data(attestation_1.data, attestation_2.data) ->
        {:error, "Attestation data is not slashable"}

      not Predicates.is_valid_indexed_attestation(state, attestation_1) ->
        {:error, "Attestation 1 is not valid"}

      not Predicates.is_valid_indexed_attestation(state, attestation_2) ->
        {:error, "Attestation 2 is not valid"}

      not Predicates.is_indices_available(
        length(state.validators),
        attestation_1.attesting_indices
      ) ->
        {:error, "Index too high attestation 1"}

      not Predicates.is_indices_available(
        length(state.validators),
        attestation_2.attesting_indices
      ) ->
        {:error, "Index too high attestation 2"}

      true ->
        {slashed_any, state} =
          Enum.uniq(attestation_1.attesting_indices)
          |> Enum.filter(fn i -> Enum.member?(attestation_2.attesting_indices, i) end)
          |> Enum.sort()
          |> Enum.reduce_while({false, state}, fn i, {slashed_any, state} ->
            slash_validator(slashed_any, state, i)
          end)

        if slashed_any do
          {:ok, state}
        else
          {:error, "Didn't slash any"}
        end
    end
  end

  defp slash_validator(slashed_any, state, i) do
    if Predicates.is_slashable_validator(
         Enum.at(state.validators, i),
         Accessors.get_current_epoch(state)
       ) do
      case Mutators.slash_validator(state, i) do
        {:ok, state} -> {:cont, {true, state}}
        {:error, _msg} -> {:halt, {false, nil}}
      end
    else
      {:cont, {slashed_any, state}}
    end
  end

  @doc """
  Process voluntary exit.
  """
  @spec process_voluntary_exit(BeaconState.t(), SszTypes.SignedVoluntaryExit.t()) ::
          {:ok, BeaconState.t()} | {:error, binary()}
  def process_voluntary_exit(state, signed_voluntary_exit) do
    voluntary_exit = signed_voluntary_exit.message
    validator = Enum.at(state.validators, voluntary_exit.validator_index)

    res =
      cond do
        not Predicates.is_indices_available(
          length(state.validators),
          [voluntary_exit.validator_index]
        ) ->
          {:error, "Too high index"}

        not Predicates.is_active_validator(validator, Accessors.get_current_epoch(state)) ->
          {:error, "Validator isn't active"}

        validator.exit_epoch != Constants.far_future_epoch() ->
          {:error, "Validator has already initiated exit"}

        Accessors.get_current_epoch(state) < voluntary_exit.epoch ->
          {:error, "Exit must specify an epoch when they become valid"}

        Accessors.get_current_epoch(state) <
            validator.activation_epoch + ChainSpec.get("SHARD_COMMITTEE_PERIOD") ->
          {:error, "Exit must specify an epoch when they become valid"}

        true ->
          Accessors.get_domain(state, Constants.domain_voluntary_exit(), voluntary_exit.epoch)
          |> then(&Misc.compute_signing_root(voluntary_exit, &1))
          |> then(&Bls.verify(validator.pubkey, &1, signed_voluntary_exit.signature))
          |> handle_verification_error()
      end

    case res do
      :ok -> initiate_validator_exit(state, voluntary_exit.validator_index)
      {:error, msg} -> {:error, msg}
    end
  end

  defp initiate_validator_exit(state, validator_index) do
    case Mutators.initiate_validator_exit(state, validator_index) do
      {:ok, validator} ->
        state = %BeaconState{
          state
          | validators: List.replace_at(state.validators, validator_index, validator)
        }

        {:ok, state}

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp handle_verification_error(is_verified) do
    case is_verified do
      {:ok, valid} when valid ->
        :ok

      {:ok, _valid} ->
        {:error, "Signature is not valid"}

      {:error, msg} ->
        {:error, msg}
    end
  end

  @doc """
  Process attestations during state transition.
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

      {updated_epoch_participation, proposer_reward_numerator} =
        update_epoch_participation(
          state,
          attesting_indices,
          initial_epoch_participation,
          participation_flag_indices
        )

      proposer_reward = compute_proposer_reward(proposer_reward_numerator)

      {:ok, proposer_index} = Accessors.get_beacon_proposer_index(state)

      bal_updated_state =
        Mutators.increase_balance(
          state,
          proposer_index,
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
    weights =
      Constants.participation_flag_weights()
      |> Stream.with_index()
      |> Enum.filter(&(elem(&1, 1) in participation_flag_indices))

    base_reward_per_increment = Accessors.get_base_reward_per_increment(state)

    state.validators
    |> Stream.zip(initial_epoch_participation)
    |> Stream.with_index()
    |> Enum.map_reduce(0, fn {{validator, participation}, i}, acc ->
      if MapSet.member?(attesting_indices, i) do
        bv_participation = BitVector.new(participation, 8)
        base_reward = Accessors.get_base_reward(validator, base_reward_per_increment)

        weights
        |> Stream.reject(&BitVector.set?(bv_participation, elem(&1, 1)))
        |> Enum.reduce({bv_participation, acc}, fn {weight, index}, {bv_participation, acc} ->
          {bv_participation |> BitVector.set(index), acc + base_reward * weight}
        end)
        |> then(fn {p, acc} -> {BitVector.to_integer(p), acc} end)
      else
        {participation, acc}
      end
    end)
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

  @doc """
  Provide randomness to the operation of the beacon chain.
  """
  @spec process_randao(BeaconState.t(), BeaconBlockBody.t()) ::
          {:ok, BeaconState.t()} | {:error, binary}
  def process_randao(
        %BeaconState{} = state,
        %BeaconBlockBody{randao_reveal: randao_reveal} = _body
      ) do
    epoch = Accessors.get_current_epoch(state)

    # Verify RANDAO reveal
    with {:ok, proposer_index} <- Accessors.get_beacon_proposer_index(state) do
      proposer = Enum.at(state.validators, proposer_index)
      domain = Accessors.get_domain(state, Constants.domain_randao(), nil)
      signing_root = Misc.compute_signing_root(epoch, SszTypes.Epoch, domain)

      if Bls.valid?(proposer.pubkey, signing_root, randao_reveal) do
        randao_mix = Accessors.get_randao_mix(state, epoch)
        hash = SszEx.hash(randao_reveal)

        # Mix in RANDAO reveal
        mix = :crypto.exor(randao_mix, hash)

        updated_randao_mixes =
          List.replace_at(
            state.randao_mixes,
            rem(epoch, ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")),
            mix
          )

        {:ok,
         %BeaconState{
           state
           | randao_mixes: updated_randao_mixes
         }}
      else
        {:error, "invalid randao reveal"}
      end
    end
  end

  @spec process_eth1_data(BeaconState.t(), BeaconBlockBody.t()) ::
          {:ok, BeaconState.t()} | {:error, binary}
  def process_eth1_data(
        %BeaconState{} = state,
        %BeaconBlockBody{eth1_data: eth1_data}
      ) do
    updated_eth1_data_votes = List.insert_at(state.eth1_data_votes, -1, eth1_data)

    if Enum.count(updated_eth1_data_votes, &(&1 == eth1_data)) * 2 >
         ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD") * ChainSpec.get("SLOTS_PER_EPOCH") do
      {:ok,
       %BeaconState{
         state
         | eth1_data: eth1_data,
           eth1_data_votes: updated_eth1_data_votes
       }}
    else
      {:ok,
       %BeaconState{
         state
         | eth1_data_votes: updated_eth1_data_votes
       }}
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
    not Predicates.is_valid_indexed_attestation(state, indexed_attestation)
  end

  defp length_of_bitstring(binary) when is_binary(binary) do
    binary
    |> :binary.bin_to_list()
    |> Enum.reduce("", fn byte, acc ->
      acc <> Integer.to_string(byte, 2)
    end)
    |> String.length()
  end

  def process_bls_to_execution_change(state, signed_address_change) do
    address_change = signed_address_change.message

    with {:ok, _} <- validate_address_change(state, address_change) do
      validator = Enum.at(state.validators, address_change.validator_index)

      with {:ok} <- validate_withdrawal_credentials(validator, address_change) do
        domain =
          Misc.compute_domain(
            Constants.domain_bls_to_execution_change(),
            genesis_validators_root: state.genesis_validators_root
          )

        signing_root = Misc.compute_signing_root(address_change, domain)

        if Bls.valid?(
             address_change.from_bls_pubkey,
             signing_root,
             signed_address_change.signature
           ) do
          new_withdrawal_credentials =
            Constants.eth1_address_withdrawal_prefix() <>
              <<0::size(88)>> <> address_change.to_execution_address

          updated_validators =
            update_validator_withdrawal_credentials(
              state.validators,
              address_change.validator_index,
              new_withdrawal_credentials
            )

          {:ok, %BeaconState{state | validators: updated_validators}}
        else
          {:error, "bls verification failed"}
        end
      end
    end
  end

  defp validate_address_change(state, address_change) do
    if address_change.validator_index < length(state.validators) do
      {:ok, address_change}
    else
      {:error, "Invalid address change"}
    end
  end

  defp validate_withdrawal_credentials(validator, address_change) do
    <<prefix::binary-size(1), address::binary-size(31)>> = validator.withdrawal_credentials
    <<_, hash::binary-size(31)>> = SszEx.hash(address_change.from_bls_pubkey)

    if prefix == Constants.bls_withdrawal_prefix() and address == hash do
      {:ok}
    else
      {:error, "Invalid withdrawal credentials"}
    end
  end

  defp update_validator_withdrawal_credentials(
         validators,
         validator_index,
         new_withdrawal_credentials
       ) do
    updated_validators =
      validators
      |> Enum.with_index(fn validator, index ->
        if index == validator_index do
          %Validator{validator | withdrawal_credentials: new_withdrawal_credentials}
        else
          validator
        end
      end)

    updated_validators
  end

  @spec process_operations(BeaconState.t(), BeaconBlockBody.t()) ::
          {:ok, BeaconState.t()} | {:error, binary}
  def process_operations(state, body) do
    # Ensure that outstanding deposits are processed up to the maximum number of deposits
    with :ok <- verify_deposits(state, body) do
      # Define a function that iterates over a list of operations and applies a given function to each element
      updated_state =
        state
        |> for_ops(body.proposer_slashings, &process_proposer_slashing/2)
        |> for_ops(body.attester_slashings, &process_attester_slashing/2)
        |> for_ops(body.attestations, &process_attestation/2)
        |> for_ops(body.deposits, &process_deposit/2)
        |> for_ops(body.voluntary_exits, &process_voluntary_exit/2)
        |> for_ops(body.bls_to_execution_changes, &process_bls_to_execution_change/2)

      {:ok, updated_state}
    end
  end

  defp for_ops(state, operations, func) do
    Enum.reduce(operations, state, fn operation, acc ->
      with {:ok, state} <- func.(acc, operation) do
        state
      end
    end)
  end

  @spec verify_deposits(BeaconState.t(), BeaconBlockBody.t()) :: :ok | {:error, binary}
  defp verify_deposits(state, body) do
    deposit_count = state.eth1_data.deposit_count - state.eth1_deposit_index
    deposit_limit = min(ChainSpec.get("MAX_DEPOSITS"), deposit_count)

    if length(body.deposits) == deposit_limit do
      :ok
    else
      {:error, "deposits length mismatch"}
    end
  end
end
