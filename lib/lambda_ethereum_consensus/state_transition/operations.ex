defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  This module contains functions for handling state transition
  """

  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Math
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Mutators
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.Utils
  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Utils.Randao
  alias Types.PendingConsolidation
  alias Types.PendingDeposit
  alias Types.PendingPartialWithdrawal

  alias Types.Attestation
  alias Types.BeaconBlock
  alias Types.BeaconBlockBody
  alias Types.BeaconBlockHeader
  alias Types.BeaconState
  alias Types.ConsolidationRequest
  alias Types.DepositRequest
  alias Types.ExecutionPayload
  alias Types.ExecutionPayloadHeader
  alias Types.SyncAggregate
  alias Types.Validator
  alias Types.Withdrawal
  alias Types.WithdrawalRequest

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
      proposer = Aja.Vector.at!(state.validators, proposer_index)

      if proposer.slashed do
        {:error, "proposer is slashed"}
      else
        {:ok, state}
      end
    end
  end

  @spec check_slots_match(Types.slot(), Types.slot()) ::
          :ok | {:error, String.t()}
  defp check_slots_match(state_slot, block_slot) do
    # Verify that the slots match
    if block_slot == state_slot do
      :ok
    else
      {:error, "slots don't match"}
    end
  end

  @spec check_block_is_newer_than_latest_block_header(Types.slot(), Types.slot()) ::
          :ok | {:error, String.t()}
  defp check_block_is_newer_than_latest_block_header(block_slot, latest_block_header_slot) do
    # Verify that the block is newer than latest block header
    if block_slot > latest_block_header_slot do
      :ok
    else
      {:error, "block is not newer than latest block header"}
    end
  end

  @spec check_proposer_index_is_correct(Types.validator_index(), BeaconState.t()) ::
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

  @spec check_parent_root_match(Types.root(), BeaconBlockHeader.t()) ::
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

    participant_pubkeys =
      committee_pubkeys
      |> Enum.with_index()
      |> Enum.filter(fn {_, index} -> BitVector.set?(aggregate.sync_committee_bits, index) end)
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

      total_proposer_reward = BitVector.count(aggregate.sync_committee_bits) * proposer_reward

      # PERF: make Map with committee_index by pubkey, then
      # Enum.map validators -> new balance all in place, without map_reduce
      state.validators
      |> get_sync_committee_indices(committee_pubkeys)
      |> Stream.with_index()
      |> Stream.map(fn {validator_index, committee_index} ->
        if BitVector.set?(aggregate.sync_committee_bits, committee_index),
          do: {validator_index, participant_reward},
          else: {validator_index, -participant_reward}
      end)
      |> Enum.reduce(state.balances, fn {validator_index, delta}, balances ->
        Aja.Vector.update_at!(balances, validator_index, &max(&1 + delta, 0))
      end)
      |> then(&%{state | balances: &1})
      |> BeaconState.increase_balance(proposer_index, total_proposer_reward)
      |> then(&{:ok, &1})
    end
  end

  defp verify_signature(pubkeys, message, signature) do
    case Bls.eth_fast_aggregate_verify(pubkeys, message, signature) do
      {:ok, true} -> :ok
      _ -> {:error, "Signature verification failed"}
    end
  end

  @spec compute_sync_aggregate_rewards(BeaconState.t()) :: {Types.gwei(), Types.gwei()}
  defp compute_sync_aggregate_rewards(state) do
    # Compute participant and proposer rewards
    total_active_balance = Accessors.get_total_active_balance(state)

    effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")
    total_active_increments = total_active_balance |> div(effective_balance_increment)

    numerator = effective_balance_increment * ChainSpec.get("BASE_REWARD_FACTOR")
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

  @spec get_sync_committee_indices(Aja.Vector.t(Validator.t()), list(Types.bls_pubkey())) ::
          list(Types.validator_index())
  defp get_sync_committee_indices(validators, committee_pubkeys) do
    pk_map =
      committee_pubkeys
      |> Stream.with_index()
      |> Enum.reduce(%{}, fn {pk, i}, map ->
        Map.update(map, pk, [i], &[i | &1])
      end)

    validators
    |> Stream.with_index()
    |> Stream.map(fn {%Validator{pubkey: pubkey}, i} -> {Map.get(pk_map, pubkey), i} end)
    |> Stream.reject(fn {v, _} -> is_nil(v) end)
    |> Stream.flat_map(fn {list, i} -> list |> Stream.map(&{&1, i}) end)
    |> Enum.sort(fn {v1, _}, {v2, _} -> v1 <= v2 end)
    |> Enum.map(fn {_, i} -> i end)
  end

  @doc """
  State transition function managing the processing & validation of the `ExecutionPayload`
  """
  @spec process_execution_payload(BeaconState.t(), BeaconBlockBody.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_execution_payload(state, %BeaconBlockBody{} = body) do
    payload = body.execution_payload

    cond do
      # Verify consistency of the parent hash with respect to the previous execution payload header
      BeaconState.merge_transition_complete?(state) and
          payload.parent_hash != state.latest_execution_payload_header.block_hash ->
        {:error, "Inconsistency in parent hash"}

      # Verify prev_randao
      payload.prev_randao !=
          Randao.get_randao_mix(state.randao_mixes, Accessors.get_current_epoch(state)) ->
        {:error, "Invalid prev_randao"}

      # Verify timestamp
      payload.timestamp != Misc.compute_timestamp_at_slot(state, state.slot) ->
        {:error, "Timestamp verification failed"}

      body.blob_kzg_commitments |> length() > ChainSpec.get("MAX_BLOBS_PER_BLOCK_ELECTRA") ->
        {:error, "Too many commitments"}

      # Cache execution payload header
      true ->
        with {:ok, transactions_root} <-
               Ssz.hash_list_tree_root_typed(
                 payload.transactions,
                 ChainSpec.get("MAX_TRANSACTIONS_PER_PAYLOAD"),
                 Types.Transaction
               ),
             {:ok, withdrawals_root} <-
               Ssz.hash_list_tree_root(
                 payload.withdrawals,
                 ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD")
               ) do
          fields =
            [
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
              withdrawals_root: withdrawals_root,
              blob_gas_used: payload.blob_gas_used,
              excess_blob_gas: payload.excess_blob_gas
            ]

          header = struct!(ExecutionPayloadHeader, fields)

          {:ok, %BeaconState{state | latest_execution_payload_header: header}}
        end
    end
  end

  @doc """
  Apply withdrawals to the state.
  """
  @spec process_withdrawals(BeaconState.t(), ExecutionPayload.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_withdrawals(
        %BeaconState{validators: validators} = state,
        %ExecutionPayload{withdrawals: withdrawals}
      ) do
    {expected_withdrawals, processed_partial_withdrawals_count} = get_expected_withdrawals(state)

    with :ok <- check_withdrawals(withdrawals, expected_withdrawals) do
      state
      |> Map.update!(:balances, &decrease_balances(&1, withdrawals))
      |> then(
        &%BeaconState{
          &1
          | pending_partial_withdrawals:
              Enum.drop(&1.pending_partial_withdrawals, processed_partial_withdrawals_count)
        }
      )
      |> update_next_withdrawal_index(withdrawals)
      |> update_next_withdrawal_validator_index(withdrawals, Aja.Vector.size(validators))
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

  @spec decrease_balances(Aja.Vector.t(Types.gwei()), list(Withdrawal.t())) :: BeaconState.t()
  defp decrease_balances(balances, withdrawals) do
    withdrawals
    |> Enum.reduce(balances, fn %Withdrawal{validator_index: index, amount: amount}, balances ->
      Aja.Vector.update_at!(balances, index, &max(&1 - amount, 0))
    end)
  end

  @spec get_expected_withdrawals(BeaconState.t()) ::
          {list(Withdrawal.t()), non_neg_integer()}
  def get_expected_withdrawals(%BeaconState{} = state) do
    # Compute the next batch of withdrawals which should be included in a block.
    epoch = Accessors.get_current_epoch(state)

    max_validators_per_withdrawals_sweep = ChainSpec.get("MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP")
    max_withdrawals_per_payload = ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD")
    # Consume pending partial withdrawals
    {processed_partial_withdrawals_count, withdrawal_index, pending_partial_withdrawals} =
      state.pending_partial_withdrawals
      |> Enum.reduce_while({0, state.next_withdrawal_index, []}, fn withdrawal,
                                                                    {processed_partial_withdrawals_count,
                                                                     withdrawal_index,
                                                                     withdrawals} ->
        process_partial_withdrawal(
          state,
          withdrawal,
          processed_partial_withdrawals_count,
          withdrawal_index,
          withdrawals
        )
      end)

    bound = state.validators |> Aja.Vector.size() |> min(max_validators_per_withdrawals_sweep)
    # Sweep for remaining.
    non_partial_withdrawals =
      Stream.zip([state.validators, state.balances])
      |> Stream.with_index()
      |> Stream.cycle()
      |> Stream.drop(state.next_withdrawal_validator_index)
      |> Stream.take(bound)
      |> Stream.map(fn {{validator, balance}, index} ->
        partially_withdrawn_balance =
          Enum.sum(
            for withdrawal <- pending_partial_withdrawals,
                withdrawal.validator_index == index,
                do: withdrawal.amount
          )

        balance = balance - partially_withdrawn_balance

        cond do
          Validator.fully_withdrawable_validator?(validator, balance, epoch) ->
            {validator, balance, index}

          Validator.partially_withdrawable_validator?(validator, balance) ->
            {validator, balance - Validator.get_max_effective_balance(validator), index}

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
          index: index + withdrawal_index,
          validator_index: validator_index,
          address: execution_address,
          amount: balance
        }
      end)

    complete_withdrawals =
      (pending_partial_withdrawals ++ Enum.to_list(non_partial_withdrawals))
      |> Enum.take(max_withdrawals_per_payload)

    {complete_withdrawals, processed_partial_withdrawals_count}
  end

  defp process_partial_withdrawal(
         state,
         withdrawal,
         processed_partial_withdrawals_count,
         withdrawal_index,
         withdrawals
       ) do
    epoch = Accessors.get_current_epoch(state)

    max_pending_partials_per_withdrawals_sweep =
      ChainSpec.get("MAX_PENDING_PARTIALS_PER_WITHDRAWALS_SWEEP")

    # We expect partial withdrawals to be ordered by withdrawable epoch
    if withdrawal.withdrawable_epoch > epoch ||
         processed_partial_withdrawals_count == max_pending_partials_per_withdrawals_sweep do
      {:halt, {processed_partial_withdrawals_count, withdrawal_index, withdrawals}}
    else
      do_process_partial_withdrawal(
        state,
        withdrawal,
        processed_partial_withdrawals_count,
        withdrawal_index,
        withdrawals
      )
    end
  end

  defp do_process_partial_withdrawal(
         state,
         withdrawal,
         processed_partial_withdrawals_count,
         withdrawal_index,
         withdrawals
       ) do
    far_future_epoch = Constants.far_future_epoch()
    min_activation_balance = ChainSpec.get("MIN_ACTIVATION_BALANCE")
    validator = Aja.Vector.at(state.validators, withdrawal.validator_index)
    has_sufficient_effective_balance = validator.effective_balance >= min_activation_balance

    has_excess_balance =
      Aja.Vector.at(state.balances, withdrawal.validator_index) > min_activation_balance

    if validator.exit_epoch == far_future_epoch && has_sufficient_effective_balance &&
         has_excess_balance do
      withdrawable_balance =
        min(
          Aja.Vector.at(state.balances, withdrawal.validator_index) -
            min_activation_balance,
          withdrawal.amount
        )

      <<_::binary-size(12), address::binary>> = validator.withdrawal_credentials

      withdrawal = %Withdrawal{
        index: withdrawal_index,
        validator_index: withdrawal.validator_index,
        address: address,
        amount: withdrawable_balance
      }

      {:cont,
       {processed_partial_withdrawals_count + 1, withdrawal_index + 1,
        withdrawals ++ [withdrawal]}}
    else
      {:cont, {processed_partial_withdrawals_count + 1, withdrawal_index, withdrawals}}
    end
  end

  @spec process_proposer_slashing(BeaconState.t(), Types.ProposerSlashing.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_proposer_slashing(state, proposer_slashing) do
    header_1 = proposer_slashing.signed_header_1.message
    header_2 = proposer_slashing.signed_header_2.message
    validators_size = Aja.Vector.size(state.validators)
    proposer = state.validators[header_1.proposer_index]

    cond do
      not Predicates.indices_available?(validators_size, [header_1.proposer_index]) ->
        {:error, "Too high index"}

      not (header_1.slot == header_2.slot) ->
        {:error, "Slots don't match"}

      not (header_1.proposer_index == header_2.proposer_index) ->
        {:error, "Proposer indices don't match"}

      not (header_1 != header_2) ->
        {:error, "Headers are same"}

      not Predicates.slashable_validator?(proposer, Accessors.get_current_epoch(state)) ->
        {:error, "Proposer is not slashable"}

      not ([proposer_slashing.signed_header_1, proposer_slashing.signed_header_2]
           |> Enum.all?(&verify_proposer_slashing(&1, state, proposer))) ->
        {:error, "Signed header 1 or 2 signature is not verified"}

      true ->
        Mutators.slash_validator(state, header_1.proposer_index)
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

  @spec process_deposit(BeaconState.t(), Types.Deposit.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_deposit(state, deposit) do
    with {:ok, deposit_data_root} <- Ssz.hash_tree_root(deposit.data) do
      if Predicates.valid_merkle_branch?(
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

  @spec process_attester_slashing(BeaconState.t(), Types.AttesterSlashing.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_attester_slashing(state, attester_slashing) do
    attestation_1 = attester_slashing.attestation_1
    attestation_2 = attester_slashing.attestation_2
    validator_size = Aja.Vector.size(state.validators)

    cond do
      not Predicates.slashable_attestation_data?(attestation_1.data, attestation_2.data) ->
        {:error, "Attestation data is not slashable"}

      not Predicates.valid_indexed_attestation?(state, attestation_1) ->
        {:error, "Attestation 1 is not valid"}

      not Predicates.valid_indexed_attestation?(state, attestation_2) ->
        {:error, "Attestation 2 is not valid"}

      not Predicates.indices_available?(validator_size, attestation_1.attesting_indices) ->
        {:error, "Index too high attestation 1"}

      not Predicates.indices_available?(validator_size, attestation_2.attesting_indices) ->
        {:error, "Index too high attestation 2"}

      true ->
        {slashed_any, state} =
          Stream.uniq(attestation_1.attesting_indices)
          |> Stream.filter(fn i -> Enum.member?(attestation_2.attesting_indices, i) end)
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
    if Aja.Vector.at!(state.validators, i)
       |> Predicates.slashable_validator?(Accessors.get_current_epoch(state)) do
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
  @spec process_voluntary_exit(BeaconState.t(), Types.SignedVoluntaryExit.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_voluntary_exit(state, signed_voluntary_exit) do
    voluntary_exit = signed_voluntary_exit.message
    validator_index = voluntary_exit.validator_index
    validator = state.validators[validator_index]
    current_epoch = Accessors.get_current_epoch(state)

    cond do
      not Predicates.indices_available?(Aja.Vector.size(state.validators), [validator_index]) ->
        {:error, "invalid index"}

      not Predicates.active_validator?(validator, current_epoch) ->
        {:error, "validator not active"}

      validator.exit_epoch != Constants.far_future_epoch() ->
        {:error, "validator already exiting"}

      current_epoch < voluntary_exit.epoch ->
        {:error, "exit not valid yet"}

      current_epoch < validator.activation_epoch + ChainSpec.get("SHARD_COMMITTEE_PERIOD") ->
        {:error, "validator cannot exit yet"}

      Accessors.get_pending_balance_to_withdraw(state, voluntary_exit.validator_index) != 0 ->
        {:error, "validator has pending withdrawals in the queue"}

      not (Misc.compute_domain(
             Constants.domain_voluntary_exit(),
             fork_version: ChainSpec.get("CAPELLA_FORK_VERSION"),
             genesis_validators_root: state.genesis_validators_root
           )
           |> then(&Misc.compute_signing_root(voluntary_exit, &1))
           |> then(&Bls.valid?(validator.pubkey, &1, signed_voluntary_exit.signature))) ->
        {:error, "invalid signature"}

      true ->
        with {:ok, {state, validator}} <- Mutators.initiate_validator_exit(state, validator_index) do
          Aja.Vector.replace_at!(state.validators, validator_index, validator)
          |> then(&{:ok, %BeaconState{state | validators: &1}})
        end
    end
  end

  @doc """
  Process attestations during state transition.
  """
  @spec process_attestation(BeaconState.t(), Attestation.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_attestation(state, attestation) do
    process_attestation_batch(state, [attestation])
  end

  @spec validate_attestation(BeaconState.t(), Attestation.t()) :: :ok | {:error, String.t()}
  def validate_attestation(
        state,
        %Attestation{data: data, aggregation_bits: aggregation_bits} = attestation
      ) do
    with :ok <- check_valid_target_epoch(data, state),
         :ok <- check_epoch_matches(data),
         :ok <- check_valid_slot_range(data, state),
         :ok <- check_data_index_zero(data),
         {:ok, committee_offset} <- check_committee_indices(attestation, state),
         :ok <- check_matching_aggregation_bits_length(aggregation_bits, committee_offset),
         {:ok, indexed_attestation} <- Accessors.get_indexed_attestation(state, attestation) do
      check_valid_indexed_attestation(state, indexed_attestation)
    end
  end

  @spec process_attestation_batch(BeaconState.t(), [Attestation.t()]) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_attestation_batch(state, attestations) do
    with {:ok, {previous_epoch_updates, current_epoch_updates}} <-
           attestations
           |> Stream.with_index()
           |> Enum.reduce_while({:ok, {Map.new(), Map.new()}}, fn
             {att, i}, {:ok, {pepu, cepu}} ->
               {:cont, fast_process_attestation(state, att, pepu, cepu, i)}

             _, {:error, _} = err ->
               {:halt, err}
           end) do
      base_reward_per_increment = Accessors.get_base_reward_per_increment(state)

      {new_previous_participation, reward_numerators} =
        update_participations(
          state,
          state.previous_epoch_participation,
          previous_epoch_updates,
          base_reward_per_increment,
          %{}
        )

      {new_current_participation, reward_numerators} =
        update_participations(
          state,
          state.current_epoch_participation,
          current_epoch_updates,
          base_reward_per_increment,
          reward_numerators
        )

      {:ok, proposer_index} = Accessors.get_beacon_proposer_index(state)

      proposer_reward =
        reward_numerators
        |> Stream.map(fn {_, numerator} -> compute_proposer_reward(numerator) end)
        |> Enum.sum()

      {:ok,
       %BeaconState{
         BeaconState.increase_balance(state, proposer_index, proposer_reward)
         | previous_epoch_participation: new_previous_participation,
           current_epoch_participation: new_current_participation
       }}
    end
  end

  defp update_participations(
         state,
         epoch_participation,
         epoch_updates,
         base_per_increment,
         reward_numerators
       ) do
    epoch_updates
    |> Enum.reduce({epoch_participation, reward_numerators}, fn
      {i, masks}, {participations, reward_numerators} ->
        validator = Aja.Vector.at!(state.validators, i)
        participation = Aja.Vector.at!(participations, i)

        masks
        |> Enum.reduce(
          {participation, reward_numerators},
          &reduce_participation_batch(validator, base_per_increment, &1, &2)
        )
        |> then(fn {participation, reward_numerators} ->
          {Aja.Vector.replace_at!(participations, i, participation), reward_numerators}
        end)
    end)
  end

  defp reduce_participation_batch(
         validator,
         base_reward_per_increment,
         {att_index, mask},
         {participation, reward_numerators}
       ) do
    base_reward = Accessors.get_base_reward(validator, base_reward_per_increment)

    weights =
      Constants.participation_flag_weights()
      |> Stream.with_index()
      |> Stream.map(fn {w, i} -> {w, 2 ** i} end)
      |> Enum.filter(fn {_, i} -> Bitwise.band(mask, i) != 0 end)

    {participation, reward} = update_participation(participation, base_reward, weights)

    {participation, Map.update(reward_numerators, att_index, reward, &(&1 + reward))}
  end

  def fast_process_attestation(
        state,
        %Attestation{data: data} = att,
        previous_epoch_updates,
        current_epoch_updates,
        attestation_index
      ) do
    with :ok <- validate_attestation(state, att),
         slot = state.slot - data.slot,
         {:ok, flag_indices} <-
           Accessors.get_attestation_participation_flag_indices(state, data, slot),
         {:ok, attesting_indices} <- Accessors.get_attesting_indices(state, att) do
      is_current_epoch = data.target.epoch == Accessors.get_current_epoch(state)
      epoch_updates = if is_current_epoch, do: current_epoch_updates, else: previous_epoch_updates

      weights_mask =
        Constants.participation_flag_weights()
        |> Stream.with_index()
        |> Stream.filter(&(elem(&1, 1) in flag_indices))
        |> Stream.map(fn {_, i} -> 2 ** i end)
        |> Enum.sum()

      v = {attestation_index, weights_mask}

      new_epoch_updates =
        attesting_indices
        |> Enum.to_list()
        |> Enum.reduce(epoch_updates, fn i, epoch_updates ->
          Map.update(epoch_updates, i, [v], &merge_masks(&1, v))
        end)

      if is_current_epoch,
        do: {:ok, {previous_epoch_updates, new_epoch_updates}},
        else: {:ok, {new_epoch_updates, current_epoch_updates}}
    end
  end

  # We simplify masks by discarding duplicates, and simplify
  # next merges by OR-ing them together.
  defp merge_masks([{_, v} | _] = masks, {_, v}), do: masks
  defp merge_masks([{_, v1} | _] = masks, {i, v2}), do: [{i, Bitwise.bor(v1, v2)} | masks]

  defp update_participation(participation, base_reward, weights) do
    weights
    |> Enum.reduce({participation, 0}, fn {weight, i}, {participation, acc} ->
      new_participation = Bitwise.bor(participation, i)
      new_acc = if new_participation == participation, do: acc, else: acc + base_reward * weight
      {new_participation, new_acc}
    end)
  end

  defp compute_proposer_reward(proposer_reward_numerator) do
    proposer_reward_denominator =
      ((Constants.weight_denominator() - Constants.proposer_weight()) *
         Constants.weight_denominator())
      |> div(Constants.proposer_weight())

    div(proposer_reward_numerator, proposer_reward_denominator)
  end

  @doc """
  Provide randomness to the operation of the beacon chain.
  """
  @spec process_randao(BeaconState.t(), BeaconBlockBody.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_randao(
        %BeaconState{} = state,
        %BeaconBlockBody{randao_reveal: randao_reveal} = _body
      ) do
    epoch = Accessors.get_current_epoch(state)

    # Verify RANDAO reveal
    with {:ok, proposer_index} <- Accessors.get_beacon_proposer_index(state) do
      proposer = Aja.Vector.at!(state.validators, proposer_index)
      domain = Accessors.get_domain(state, Constants.domain_randao())
      signing_root = Misc.compute_signing_root(epoch, TypeAliases.epoch(), domain)

      if Bls.valid?(proposer.pubkey, signing_root, randao_reveal) do
        randao_mix = Randao.get_randao_mix(state.randao_mixes, epoch)
        hash = SszEx.hash(randao_reveal)

        # Mix in RANDAO reveal
        mix = :crypto.exor(randao_mix, hash)

        updated_randao_mixes = Randao.replace_randao_mix(state.randao_mixes, epoch, mix)

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
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_eth1_data(
        %BeaconState{} = state,
        %BeaconBlockBody{eth1_data: eth1_data}
      ) do
    updated_eth1_data_votes = List.insert_at(state.eth1_data_votes, -1, eth1_data)
    updated_state = %{state | eth1_data_votes: updated_eth1_data_votes}

    slots_per_eth1_voting_period =
      ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD") * ChainSpec.get("SLOTS_PER_EPOCH")

    if Enum.count(updated_eth1_data_votes, &(&1 == eth1_data)) * 2 > slots_per_eth1_voting_period do
      {:ok, %{updated_state | eth1_data: eth1_data}}
    else
      {:ok, updated_state}
    end
  end

  defp check_valid_target_epoch(data, state) do
    if data.target.epoch in [
         Accessors.get_previous_epoch(state),
         Accessors.get_current_epoch(state)
       ] do
      :ok
    else
      {:error, "Invalid target epoch"}
    end
  end

  defp check_epoch_matches(data) do
    if data.target.epoch == Misc.compute_epoch_at_slot(data.slot) do
      :ok
    else
      {:error, "Epoch mismatch"}
    end
  end

  defp check_valid_slot_range(data, state) do
    if data.slot + ChainSpec.get("MIN_ATTESTATION_INCLUSION_DELAY") <= state.slot do
      :ok
    else
      {:error, "Invalid slot range"}
    end
  end

  defp check_committee_count(comittee_index, data, state) do
    if comittee_index >= Accessors.get_committee_count_per_slot(state, data.target.epoch) do
      {:error, "Comitee index exceeds committee count"}
    else
      :ok
    end
  end

  defp check_matching_aggregation_bits_length(aggregation_bits, committe_offset) do
    aggregation_bits_length = BitList.length(aggregation_bits)

    if aggregation_bits_length == committe_offset do
      :ok
    else
      {:error,
       "Mismatched length. aggregation_bits: #{aggregation_bits_length}. committee_offset: #{committe_offset}"}
    end
  end

  defp check_valid_indexed_attestation(state, indexed_attestation) do
    if Predicates.valid_indexed_attestation?(state, indexed_attestation) do
      :ok
    else
      {:error, "Invalid signature"}
    end
  end

  defp check_data_index_zero(%{index: 0}), do: :ok
  defp check_data_index_zero(_data), do: {:error, "Data index should be zero"}

  defp check_committee_attesters_exists(committee, aggregation_bits, committee_offset) do
    committee
    |> Enum.with_index()
    |> Enum.any?(&BitList.set?(aggregation_bits, elem(&1, 1) + committee_offset))
    |> case do
      true -> :ok
      false -> {:error, "No committee attesters exist"}
    end
  end

  defp check_committee_indices(attestation, state) do
    %Attestation{data: data, aggregation_bits: aggregation_bits, committee_bits: committee_bits} =
      attestation

    committee_bits
    |> Accessors.get_committee_indices()
    |> Enum.reduce_while({:ok, 0}, fn committee_index, {:ok, committee_offset} ->
      with :ok <- check_committee_count(committee_index, data, state),
           {:ok, committee} <- Accessors.get_beacon_committee(state, data.slot, committee_index),
           :ok <- check_committee_attesters_exists(committee, aggregation_bits, committee_offset) do
        {:cont, {:ok, committee_offset + length(committee)}}
      else
        error -> {:halt, error}
      end
    end)
  end

  def process_bls_to_execution_change(state, signed_address_change) do
    address_change = signed_address_change.message

    with :ok <- validate_address_change(state, address_change),
         validator = Aja.Vector.at!(state.validators, address_change.validator_index),
         :ok <- validate_withdrawal_credentials(validator, address_change) do
      signing_root =
        Misc.compute_domain(
          Constants.domain_bls_to_execution_change(),
          genesis_validators_root: state.genesis_validators_root
        )
        |> then(&Misc.compute_signing_root(address_change, &1))

      if Bls.valid?(
           address_change.from_bls_pubkey,
           signing_root,
           signed_address_change.signature
         ) do
        [
          Constants.eth1_address_withdrawal_prefix(),
          <<0::size(88)>>,
          address_change.to_execution_address
        ]
        |> Enum.join()
        |> then(&%Validator{validator | withdrawal_credentials: &1})
        |> then(&Aja.Vector.replace_at!(state.validators, address_change.validator_index, &1))
        |> then(&{:ok, %BeaconState{state | validators: &1}})
      else
        {:error, "bls verification failed"}
      end
    end
  end

  defp validate_address_change(state, address_change) do
    if address_change.validator_index < Aja.Vector.size(state.validators) do
      :ok
    else
      {:error, "Invalid address change"}
    end
  end

  defp validate_withdrawal_credentials(validator, address_change) do
    <<prefix::binary-size(1), address::binary-size(31)>> = validator.withdrawal_credentials
    <<_, hash::binary-size(31)>> = SszEx.hash(address_change.from_bls_pubkey)

    if prefix == Constants.bls_withdrawal_prefix() and address == hash do
      :ok
    else
      {:error, "Invalid withdrawal credentials"}
    end
  end

  @spec process_deposit_request(BeaconState.t(), DepositRequest.t()) :: {:ok, BeaconState.t()}
  def process_deposit_request(state, deposit_request) do
    start_index =
      if state.deposit_requests_start_index == Constants.unset_deposit_requests_start_index(),
        do: deposit_request.index,
        else: state.deposit_requests_start_index

    deposit = %PendingDeposit{
      pubkey: deposit_request.pubkey,
      withdrawal_credentials: deposit_request.withdrawal_credentials,
      amount: deposit_request.amount,
      signature: deposit_request.signature,
      slot: state.slot
    }

    {:ok,
     %BeaconState{
       state
       | deposit_requests_start_index: start_index,
         pending_deposits: state.pending_deposits ++ [deposit]
     }}
  end

  @spec process_withdrawal_request(BeaconState.t(), WithdrawalRequest.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_withdrawal_request(state, withdrawal_request) do
    amount = withdrawal_request.amount
    is_full_exit_request = amount == Constants.full_exit_request_amount()
    request_pubkey = withdrawal_request.validator_pubkey
    current_epoch = Accessors.get_current_epoch(state)
    far_future_epoch = Constants.far_future_epoch()

    with false <- partial_withdrawal_on_full_queue?(state, is_full_exit_request),
         {validator, validator_index} <- find_validator(state, request_pubkey),
         true <-
           not invalid_withdrawal_credentials?(validator, withdrawal_request.source_address),
         true <- Predicates.active_validator?(validator, current_epoch),
         true <- validator.exit_epoch == far_future_epoch,
         true <-
           current_epoch >= validator.activation_epoch + ChainSpec.get("SHARD_COMMITTEE_PERIOD") do
      pending_balance_to_withdraw =
        Accessors.get_pending_balance_to_withdraw(state, validator_index)

      withdrawal_request_type =
        cond do
          is_full_exit_request and pending_balance_to_withdraw == 0 -> :full_exit
          is_full_exit_request -> :full_exit_with_pending_balance
          true -> :partial_exit
        end

      handle_valid_withdrawal_request(
        state,
        validator,
        validator_index,
        amount,
        pending_balance_to_withdraw,
        withdrawal_request_type
      )
    else
      _ ->
        {:ok, state}
    end
  end

  defp partial_withdrawal_on_full_queue?(state, is_full_exit_request) do
    length(state.pending_partial_withdrawals) ==
      ChainSpec.get("PENDING_PARTIAL_WITHDRAWALS_LIMIT") && !is_full_exit_request
  end

  defp invalid_withdrawal_credentials?(validator, address) do
    has_correct_credential = Validator.has_execution_withdrawal_credential(validator)

    is_correct_source_address =
      case validator.withdrawal_credentials do
        <<_::binary-size(12), validator_address::binary>> -> validator_address == address
        _ -> false
      end

    !(has_correct_credential && is_correct_source_address)
  end

  @spec find_validator(Types.BeaconState.t(), Types.bls_pubkey()) ::
          {Types.Validator.t(), non_neg_integer()} | nil
  defp find_validator(state, request_pubkey) do
    state.validators
    |> Aja.Enum.find_index(fn validator -> validator.pubkey == request_pubkey end)
    |> then(fn
      nil -> nil
      index -> {Aja.Vector.at(state.validators, index), index}
    end)
  end

  defp handle_valid_withdrawal_request(state, _, validator_index, _, _, :full_exit) do
    with {:ok, {state, validator}} <- Mutators.initiate_validator_exit(state, validator_index) do
      {:ok,
       %Types.BeaconState{
         state
         | validators: Aja.Vector.replace_at(state.validators, validator_index, validator)
       }}
    end
  end

  defp handle_valid_withdrawal_request(state, _, _, _, _, :full_exit_with_pending_balance),
    do: {:ok, state}

  defp handle_valid_withdrawal_request(
         state,
         validator,
         validator_index,
         amount,
         pending_balance_to_withdraw,
         :partial_exit
       ) do
    min_activation_balance = ChainSpec.get("MIN_ACTIVATION_BALANCE")

    has_sufficient_effective_balance =
      validator.effective_balance >= min_activation_balance

    has_excess_balance =
      Aja.Vector.at(state.balances, validator_index) >
        min_activation_balance + pending_balance_to_withdraw

    if Validator.has_compounding_withdrawal_credential(validator) &&
         has_sufficient_effective_balance && has_excess_balance do
      to_withdraw =
        min(
          Aja.Vector.at(state.balances, validator_index) - min_activation_balance -
            pending_balance_to_withdraw,
          amount
        )

      state = Mutators.compute_exit_epoch_and_update_churn(state, to_withdraw)
      exit_queue_epoch = state.earliest_exit_epoch

      withdrawable_epoch =
        exit_queue_epoch + ChainSpec.get("MIN_VALIDATOR_WITHDRAWABILITY_DELAY")

      pending_partial_withdrawal = %PendingPartialWithdrawal{
        validator_index: validator_index,
        amount: to_withdraw,
        withdrawable_epoch: withdrawable_epoch
      }

      {:ok,
       %BeaconState{
         state
         | # We should make sure that partial withdrawals are ordered by withdrawable epoch
           pending_partial_withdrawals:
             state.pending_partial_withdrawals ++ [pending_partial_withdrawal]
       }}
    else
      {:ok, state}
    end
  end

  @spec process_consolidation_request(BeaconState.t(), ConsolidationRequest.t()) ::
          {:ok, BeaconState.t()}
  def process_consolidation_request(state, consolidation_request) do
    request_type =
      if valid_switch_to_compounding_request?(state, consolidation_request),
        do: :compounding,
        else: :consolidation

    do_process_consolidation_request(state, consolidation_request, request_type)
  end

  defp do_process_consolidation_request(state, consolidation_request, :compounding) do
    case find_validator(state, consolidation_request.source_pubkey) do
      {_validator, validator_index} ->
        {:ok, Mutators.switch_to_compounding_validator(state, validator_index)}

      nil ->
        {:ok, state}
    end
  end

  defp do_process_consolidation_request(state, consolidation_request, :consolidation) do
    with :ok <- verify_consolidation_request(state, consolidation_request),
         {source_validator, source_index} <-
           find_validator(state, consolidation_request.source_pubkey),
         {_target_validator, target_index} <-
           find_validator(state, consolidation_request.target_pubkey),
         :ok <-
           verify_consolidation_validators(
             state,
             source_index,
             target_index,
             consolidation_request
           ) do
      state =
        Mutators.compute_consolidation_epoch_and_update_churn(
          state,
          source_validator.effective_balance
        )

      consolidation_epoch = state.earliest_consolidation_epoch

      withdrawable_epoch =
        consolidation_epoch + ChainSpec.get("MIN_VALIDATOR_WITHDRAWABILITY_DELAY")

      updated_source_validator = %Validator{
        source_validator
        | exit_epoch: consolidation_epoch,
          withdrawable_epoch: withdrawable_epoch
      }

      pending_consolidation = %PendingConsolidation{
        source_index: source_index,
        target_index: target_index
      }

      updated_state = %BeaconState{
        state
        | validators:
            Aja.Vector.replace_at(state.validators, source_index, updated_source_validator),
          pending_consolidations: state.pending_consolidations ++ [pending_consolidation]
      }

      {:ok, updated_state}
    else
      _error -> {:ok, state}
    end
  end

  defp verify_consolidation_request(state, consolidation_request) do
    cond do
      consolidation_request.source_pubkey == consolidation_request.target_pubkey ->
        {:error, :source_target_same}

      # If the pending consolidations queue is full, consolidation requests are ignored
      length(state.pending_consolidations) >= ChainSpec.get("PENDING_CONSOLIDATIONS_LIMIT") ->
        {:error, :queue_full}

      # If there is too little available consolidation churn limit, consolidation requests are ignored
      Accessors.get_consolidation_churn_limit(state) <= ChainSpec.get("MIN_ACTIVATION_BALANCE") ->
        {:error, :churn_limit_not_met}

      true ->
        :ok
    end
  end

  defp verify_consolidation_validators(state, source_index, target_index, consolidation_request) do
    source_validator = Aja.Vector.at(state.validators, source_index)
    target_validator = Aja.Vector.at(state.validators, target_index)
    current_epoch = Accessors.get_current_epoch(state)
    far_future_epoch = Constants.far_future_epoch()

    cond do
      invalid_consolidation_request_credentials?(
        source_validator,
        target_validator,
        consolidation_request
      ) ->
        {:error, :invalid_credentials}

      # Verify the source and the target are active
      !Predicates.active_validator?(source_validator, current_epoch) ||
          !Predicates.active_validator?(target_validator, current_epoch) ->
        {:error, :validator_not_active}

      # Verify exits for source and target have not been initiated
      source_validator.exit_epoch != far_future_epoch ||
          target_validator.exit_epoch != far_future_epoch ->
        {:error, :validator_exiting}

      # Verify the source has been active long enough
      current_epoch <
          source_validator.activation_epoch + ChainSpec.get("SHARD_COMMITTEE_PERIOD") ->
        {:error, :validator_not_active_long_enough}

      # Verify the source has no pending withdrawals in the queue
      Accessors.get_pending_balance_to_withdraw(state, source_index) > 0 ->
        {:error, :validator_has_pending_balance}

      # Initiate source validator exit and append pending consolidation
      true ->
        :ok
    end
  end

  defp invalid_consolidation_request_credentials?(
         source_validator,
         target_validator,
         consolidation_request
       ) do
    invalid_withdrawal_credentials?(source_validator, consolidation_request.source_address) ||
      not Validator.has_compounding_withdrawal_credential(target_validator)
  end

  @spec valid_switch_to_compounding_request?(BeaconState.t(), ConsolidationRequest.t()) ::
          boolean()
  def valid_switch_to_compounding_request?(state, consolidation_request) do
    current_epoch = Accessors.get_current_epoch(state)
    far_future_epoch = Constants.far_future_epoch()

    # Verify pubkey exists
    with {source_validator, _source_index} <-
           find_validator(state, consolidation_request.source_pubkey),
         # Switch to compounding requires source and target be equal
         true <- consolidation_request.source_pubkey == consolidation_request.target_pubkey,
         # Verify request has been authorized
         true <-
           not invalid_withdrawal_credentials?(
             source_validator,
             consolidation_request.source_address
           ),
         # Verify source withdrawal credentials
         true <- Validator.has_eth1_withdrawal_credential(source_validator),
         # Verify the source is active
         true <- Predicates.active_validator?(source_validator, current_epoch),
         # Verify exit for source has not been initiated
         true <- source_validator.exit_epoch == far_future_epoch do
      true
    else
      _ ->
        false
    end
  end

  @spec process_operations(BeaconState.t(), BeaconBlockBody.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_operations(state, body) do
    # Ensure that outstanding deposits are processed up to the maximum number of deposits
    with :ok <- verify_deposits(state, body) do
      {:ok, state}
      |> for_ops(:proposer_slashing, body.proposer_slashings, &process_proposer_slashing/2)
      |> for_ops(:attester_slashing, body.attester_slashings, &process_attester_slashing/2)
      |> apply_op(:attestation_batch, &process_attestation_batch(&1, body.attestations))
      |> for_ops(:deposit, body.deposits, &process_deposit/2)
      |> for_ops(:voluntary_exit, body.voluntary_exits, &process_voluntary_exit/2)
      |> for_ops(
        :bls_to_execution_change,
        body.bls_to_execution_changes,
        &process_bls_to_execution_change/2
      )
      |> for_ops(:deposit_request, body.execution_requests.deposits, &process_deposit_request/2)
      |> for_ops(
        :withdrawal_request,
        body.execution_requests.withdrawals,
        &process_withdrawal_request/2
      )
      |> for_ops(
        :consolidation_request,
        body.execution_requests.consolidations,
        &process_consolidation_request/2
      )
    end
  end

  defp apply_op(acc, op_name, func) do
    Metrics.span_operation(:on_block, :process_block_operations, op_name, fn ->
      Utils.map_ok(acc, func)
    end)
  end

  defp for_ops(acc, op_name, operations, func) do
    Metrics.span_operation(:on_block, :process_block_operations, op_name, fn ->
      Enum.reduce_while(operations, acc, fn
        operation, {:ok, state} -> {:cont, func.(state, operation)}
        _, {:error, reason} -> {:halt, {:error, reason}}
      end)
    end)
  end

  @spec verify_deposits(BeaconState.t(), BeaconBlockBody.t()) :: :ok | {:error, String.t()}
  defp verify_deposits(state, body) do
    eth1_deposit_index_limit =
      min(state.eth1_data.deposit_count, state.deposit_requests_start_index)

    max_deposits = ChainSpec.get("MAX_DEPOSITS")

    cond do
      state.eth1_deposit_index < eth1_deposit_index_limit and
          length(body.deposits) ==
            min(max_deposits, eth1_deposit_index_limit - state.eth1_deposit_index) ->
        :ok

      state.eth1_deposit_index >= eth1_deposit_index_limit and Enum.empty?(body.deposits) ->
        :ok

      true ->
        {:error, "Invalid deposits"}
    end
  end
end
