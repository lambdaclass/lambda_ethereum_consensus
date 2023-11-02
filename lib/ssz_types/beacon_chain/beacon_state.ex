defmodule SszTypes.BeaconState do
  @moduledoc """
  Struct definition for `BeaconState`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :genesis_time,
    :genesis_validators_root,
    :slot,
    :fork,
    :latest_block_header,
    :block_roots,
    :state_roots,
    :historical_roots,
    :eth1_data,
    :eth1_data_votes,
    :eth1_deposit_index,
    :validators,
    :balances,
    :randao_mixes,
    :slashings,
    :previous_epoch_participation,
    :current_epoch_participation,
    :justification_bits,
    :previous_justified_checkpoint,
    :current_justified_checkpoint,
    :finalized_checkpoint,
    :inactivity_scores,
    :current_sync_committee,
    :next_sync_committee,
    :latest_execution_payload_header,
    :next_withdrawal_index,
    :next_withdrawal_validator_index,
    :historical_summaries
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # Versioning
          genesis_time: SszTypes.uint64(),
          genesis_validators_root: SszTypes.root(),
          slot: SszTypes.slot(),
          fork: SszTypes.Fork.t(),
          # History
          latest_block_header: SszTypes.BeaconBlockHeader.t(),
          block_roots: list(SszTypes.root()),
          state_roots: list(SszTypes.root()),
          # Frozen in Capella, replaced by historical_summaries
          historical_roots: list(SszTypes.root()),
          # Eth1
          eth1_data: SszTypes.Eth1Data.t(),
          eth1_data_votes: list(SszTypes.Eth1Data.t()),
          eth1_deposit_index: SszTypes.uint64(),
          # Registry
          validators: list(SszTypes.Validator.t()),
          balances: list(SszTypes.gwei()),
          # Randomness
          randao_mixes: list(SszTypes.bytes32()),
          # Slashings
          # Per-epoch sums of slashed effective balances
          slashings: list(SszTypes.gwei()),
          # Participation
          previous_epoch_participation: list(SszTypes.participation_flags()),
          current_epoch_participation: list(SszTypes.participation_flags()),
          # Finality
          # Bit set for every recent justified epoch
          justification_bits: SszTypes.bitvector(),
          previous_justified_checkpoint: SszTypes.Checkpoint.t(),
          current_justified_checkpoint: SszTypes.Checkpoint.t(),
          finalized_checkpoint: SszTypes.Checkpoint.t(),
          # Inactivity
          inactivity_scores: list(SszTypes.uint64()),
          # Sync
          current_sync_committee: SszTypes.SyncCommittee.t(),
          next_sync_committee: SszTypes.SyncCommittee.t(),
          # Execution
          # [Modified in Capella]
          latest_execution_payload_header: SszTypes.ExecutionPayloadHeader.t(),
          # Withdrawals
          # [New in Capella]
          next_withdrawal_index: SszTypes.withdrawal_index(),
          # [New in Capella]
          next_withdrawal_validator_index: SszTypes.withdrawal_index(),
          # Deep history valid from Capella onwards
          # [New in Capella]
          historical_summaries: list(SszTypes.HistoricalSummary.t())
        }

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Predicates

  @doc """
    Decrease the validator balance at index ``index`` by ``delta``, with underflow protection.
  """
  @spec decrease_balance(t(), SszTypes.validator_index(), SszTypes.gwei()) :: t()
  def decrease_balance(%__MODULE__{balances: balances} = state, index, delta) do
    current_balance = Enum.fetch!(balances, index)

    %{
      state
      | balances: List.replace_at(balances, index, max(current_balance - delta, 0))
    }
  end

  @doc """
  Return the deltas for a given ``flag_index`` by scanning through the participation flags.
  """
  @spec get_flag_index_deltas(t(), integer) :: {list(SszTypes.gwei()), list(SszTypes.gwei())}
  def get_flag_index_deltas(state, flag_index) do
    previous_epoch = Accessors.get_previous_epoch(state)

    {:ok, unslashed_participating_indices} =
      Accessors.get_unslashed_participating_indices(state, flag_index, previous_epoch)

    weight = Enum.at(Constants.participation_flag_weights(), flag_index)

    unslashed_participating_balance =
      Accessors.get_total_balance(state, unslashed_participating_indices)

    effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")

    unslashed_participating_increments =
      div(unslashed_participating_balance, effective_balance_increment)

    active_increments =
      div(Accessors.get_total_active_balance(state), effective_balance_increment)

    weight_denominator = Constants.weight_denominator()

    penalties = rewards = List.duplicate(0, length(state.validators))

    Accessors.get_eligible_validator_indices(state)
    |> Enum.reduce({rewards, penalties}, fn index, {rewards, penalties} ->
      base_reward = Accessors.get_base_reward(state, index)

      cond do
        MapSet.member?(unslashed_participating_indices, index) ->
          if Predicates.is_in_inactivity_leak(state) do
            {rewards, penalties}
          else
            reward_numerator = base_reward * weight * unslashed_participating_increments
            reward = div(reward_numerator, active_increments * weight_denominator)
            {List.update_at(rewards, index, &(&1 + reward)), penalties}
          end

        flag_index != Constants.timely_head_flag_index() ->
          penalty = div(base_reward * weight, weight_denominator)
          {rewards, List.update_at(penalties, index, &(&1 + penalty))}

        true ->
          {rewards, penalties}
      end
    end)
  end

  @doc """
  Return the inactivity penalty deltas by considering timely
  target participation flags and inactivity scores.
  """
  @spec get_inactivity_penalty_deltas(t()) :: {list(SszTypes.gwei()), list(SszTypes.gwei())}
  def get_inactivity_penalty_deltas(state) do
    n_validator = length(state.validators)
    rewards = List.duplicate(0, n_validator)
    penalties = List.duplicate(0, n_validator)
    previous_epoch = Accessors.get_previous_epoch(state)

    matching_target_indices =
      state
      |> Accessors.get_unslashed_participating_indices(
        Constants.timely_target_flag_index(),
        previous_epoch
      )
      |> MapSet.new()

    state
    |> Accessors.get_eligible_validator_indices()
    |> Stream.filter(&(not MapSet.member?(matching_target_indices, &1)))
    |> Enum.reduce({rewards, penalties}, fn index, {rw, pn} ->
      penalty_numerator =
        Enum.at(state.validators, index).effective_balance *
          Enum.at(state.inactivity_scores, index)

      penalty_denominator =
        ChainSpec.get("INACTIVITY_SCORE_BIAS") *
          ChainSpec.get("INACTIVITY_PENALTY_QUOTIENT_BELLATRIX")

      penalty = div(penalty_numerator, penalty_denominator)
      {rw, List.update_at(pn, index, &(&1 + penalty))}
    end)
  end
end
