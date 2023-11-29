defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  This module contains functions for handling state transition
  """

  alias LambdaEthereumConsensus.Engine
  alias LambdaEthereumConsensus.StateTransition.{Accessors, Misc, Mutators, Predicates}
  alias LambdaEthereumConsensus.Utils.BitVector
  alias SszTypes.BeaconBlockBody

  alias SszTypes.{
    Attestation,
    BeaconBlock,
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
  def process_sync_aggregate(
        %BeaconState{
          slot: slot,
          current_sync_committee: current_sync_committee,
          validators: validators
        } = state,
        %SyncAggregate{
          sync_committee_bits: sync_committee_bits,
          sync_committee_signature: sync_committee_signature
        }
      ) do
    # Verify sync committee aggregate signature signing over the previous slot block root
    committee_pubkeys = current_sync_committee.pubkeys

    # TODO: Change bitvectors to be in little-endian instead of converting manually
    sync_committee_bits_as_num = sync_committee_bits |> :binary.decode_unsigned()

    sync_committee_bits =
      <<sync_committee_bits_as_num::unsigned-integer-little-size(bit_size(sync_committee_bits))>>

    participant_pubkeys =
      Enum.with_index(committee_pubkeys)
      |> Enum.filter(fn {_, index} -> BitVector.set?(sync_committee_bits, index) end)
      |> Enum.map(fn {public_key, _} -> public_key end)

    previous_slot = max(slot, 1) - 1
    epoch = Misc.compute_epoch_at_slot(previous_slot)
    domain = Accessors.get_domain(state, Constants.domain_sync_committee(), epoch)

    with {:ok, block_root} <- Accessors.get_block_root_at_slot(state, previous_slot),
         signing_root <- Misc.compute_signing_root(block_root, domain),
         {:ok, true} <-
           Bls.eth_fast_aggregate_verify(
             participant_pubkeys,
             signing_root,
             sync_committee_signature
           ) do
      # Compute participant and proposer rewards
      {participant_reward, proposer_reward} = compute_sync_aggregate_rewards(state)

      # Apply participant and proposer rewards
      committee_indices = get_sync_committee_indices(validators, committee_pubkeys)

      Stream.with_index(committee_indices)
      |> Enum.reduce_while({:ok, state}, fn {participant_index, index}, {_, state} ->
        if BitVector.set?(sync_committee_bits, index) do
          state
          |> increase_balance_or_return_error(
            participant_index,
            participant_reward,
            proposer_reward
          )
        else
          {:cont,
           {:ok, state |> Mutators.decrease_balance(participant_index, participant_reward)}}
        end
      end)
    else
      {:ok, false} -> {:error, "Signature verification failed"}
      {:error, message} -> {:error, message}
    end
  end

  @spec compute_sync_aggregate_rewards(BeaconState.t()) :: {SszTypes.gwei(), SszTypes.gwei()}
  defp compute_sync_aggregate_rewards(state) do
    # Compute participant and proposer rewards
    total_active_increments =
      div(
        Accessors.get_total_active_balance(state),
        ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")
      )

    total_base_rewards =
      Accessors.get_base_reward_per_increment(state) * total_active_increments

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
    # Apply participant and proposer rewards
    all_pubkeys =
      validators
      |> Enum.map(fn %Validator{pubkey: pubkey} -> pubkey end)

    committee_pubkeys
    |> Enum.with_index()
    |> Enum.map(fn {public_key, _} ->
      Enum.find_index(all_pubkeys, fn x -> x == public_key end)
    end)
  end

  @spec increase_balance_or_return_error(
          BeaconState.t(),
          SszTypes.validator_index(),
          SszTypes.gwei(),
          SszTypes.gwei()
        ) :: {:cont, {:ok, BeaconState.t()}} | {:halt, {:error, String.t()}}
  defp increase_balance_or_return_error(
         %BeaconState{} = state,
         participant_index,
         participant_reward,
         proposer_reward
       ) do
    case Accessors.get_beacon_proposer_index(state) do
      {:ok, proposer_index} ->
        {:cont,
         {:ok,
          state
          |> Mutators.increase_balance(participant_index, participant_reward)
          |> Mutators.increase_balance(proposer_index, proposer_reward)}}

      {:error, _} ->
        {:halt, {:error, "Error getting beacon proposer index"}}
    end
  end

  @doc """
  State transition function managing the processing & validation of the `ExecutionPayload`
  """
  @spec process_execution_payload(BeaconState.t(), ExecutionPayload.t(), boolean()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}

  def process_execution_payload(_state, _payload, false) do
    {:error, "Invalid execution payload"}
  end

  def process_execution_payload(state, payload, _execution_valid) do
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
      Engine.Execution.verify_and_notify_new_payload(payload) != {:ok, true} ->
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

    length_of_validators = length(validators)

    with {:ok, state} <- decrease_balances(state, withdrawals, expected_withdrawals) do
      {:ok,
       state
       |> update_next_withdrawal_index(expected_withdrawals)
       |> update_next_withdrawal_validator_index(expected_withdrawals, length_of_validators)}
    end
  end

  @spec update_next_withdrawal_index(BeaconState.t(), list(Withdrawal.t())) :: BeaconState.t()
  defp update_next_withdrawal_index(state, expected_withdrawals) do
    # Update the next withdrawal index if this block contained withdrawals
    length_of_expected_withdrawals = length(expected_withdrawals)

    case length_of_expected_withdrawals != 0 do
      true ->
        latest_withdrawal = List.last(expected_withdrawals)
        %BeaconState{state | next_withdrawal_index: latest_withdrawal.index + 1}

      false ->
        state
    end
  end

  @spec update_next_withdrawal_validator_index(BeaconState.t(), list(Withdrawal.t()), integer) ::
          BeaconState.t()
  defp update_next_withdrawal_validator_index(state, expected_withdrawals, length_of_validators) do
    length_of_expected_withdrawals = length(expected_withdrawals)

    case length_of_expected_withdrawals == ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD") do
      # Update the next validator index to start the next withdrawal sweep
      true ->
        latest_withdrawal = List.last(expected_withdrawals)
        next_validator_index = rem(latest_withdrawal.validator_index + 1, length_of_validators)
        %BeaconState{state | next_withdrawal_validator_index: next_validator_index}

      # Advance sweep by the max length of the sweep if there was not a full set of withdrawals
      false ->
        next_index =
          state.next_withdrawal_validator_index +
            ChainSpec.get("MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP")

        next_validator_index = rem(next_index, length_of_validators)
        %BeaconState{state | next_withdrawal_validator_index: next_validator_index}
    end
  end

  @spec decrease_balances(BeaconState.t(), list(Withdrawal.t()), list(Withdrawal.t())) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  defp decrease_balances(_state, withdrawals, expected_withdrawals)
       when length(withdrawals) !== length(expected_withdrawals) do
    {:error, "expected withdrawals don't match the state withdrawals in length"}
  end

  @spec decrease_balances(BeaconState.t(), list(Withdrawal.t()), list(Withdrawal.t())) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  defp decrease_balances(state, withdrawals, expected_withdrawals) do
    Enum.zip(expected_withdrawals, withdrawals)
    |> Enum.reduce_while({:ok, state}, &decrease_or_halt/2)
  end

  defp decrease_or_halt({expected_withdrawal, withdrawal}, _)
       when expected_withdrawal !== withdrawal do
    {:halt, {:error, "withdrawal != expected_withdrawal"}}
  end

  defp decrease_or_halt({_, withdrawal}, {:ok, state}) do
    {:cont,
     {:ok, BeaconState.decrease_balance(state, withdrawal.validator_index, withdrawal.amount)}}
  end

  @spec get_expected_withdrawals(BeaconState.t()) :: list(Withdrawal.t())
  defp get_expected_withdrawals(
         %BeaconState{
           next_withdrawal_index: next_withdrawal_index,
           next_withdrawal_validator_index: next_withdrawal_validator_index,
           validators: validators,
           balances: balances
         } = state
       ) do
    # Compute the next batch of withdrawals which should be included in a block.
    epoch = Accessors.get_current_epoch(state)
    withdrawal_index = next_withdrawal_index
    validator_index = next_withdrawal_validator_index
    max_validators_per_withdrawals_sweep = ChainSpec.get("MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP")
    bound = min(length(validators), max_validators_per_withdrawals_sweep)

    {withdrawals, _, _} =
      Enum.reduce_while(0..(bound - 1), {[], validator_index, withdrawal_index}, fn _,
                                                                                    {withdrawals,
                                                                                     validator_index,
                                                                                     withdrawal_index} ->
        validator = Enum.fetch!(validators, validator_index)
        balance = Enum.fetch!(balances, validator_index)
        %Validator{withdrawal_credentials: withdrawal_credentials} = validator

        {withdrawals, withdrawal_index} =
          cond do
            Validator.is_fully_withdrawable_validator(validator, balance, epoch) ->
              <<_::binary-size(12), execution_address::binary>> = withdrawal_credentials

              withdrawal = %Withdrawal{
                index: withdrawal_index,
                validator_index: validator_index,
                address: execution_address,
                amount: balance
              }

              withdrawals = [withdrawal | withdrawals]
              withdrawal_index = withdrawal_index + 1

              {withdrawals, withdrawal_index}

            Validator.is_partially_withdrawable_validator(validator, balance) ->
              <<_::binary-size(12), execution_address::binary>> = withdrawal_credentials
              max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

              withdrawal = %Withdrawal{
                index: withdrawal_index,
                validator_index: validator_index,
                address: execution_address,
                amount: balance - max_effective_balance
              }

              withdrawals = [withdrawal | withdrawals]
              withdrawal_index = withdrawal_index + 1

              {withdrawals, withdrawal_index}

            true ->
              {withdrawals, withdrawal_index}
          end

        max_withdrawals_per_payload = ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD")

        if length(withdrawals) == max_withdrawals_per_payload do
          {:halt, {withdrawals, validator_index, withdrawal_index}}
        else
          validator_index = rem(validator_index + 1, length(validators))
          {:cont, {withdrawals, validator_index, withdrawal_index}}
        end
      end)

    Enum.reverse(withdrawals)
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

      {proposer_reward_numerator, updated_epoch_participation} =
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
        hash = :crypto.hash(:sha256, randao_reveal)

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
    <<_, hash::binary-size(31)>> = :crypto.hash(:sha256, address_change.from_bls_pubkey)

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
end
