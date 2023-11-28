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
  Checks if state is pre or post merge
  """
  @spec is_merge_transition_complete(SszTypes.BeaconState.t()) :: boolean()
  def is_merge_transition_complete(state) do
    state.latest_execution_payload_header !=
      struct(SszTypes.ExecutionPayload, SszTypes.ExecutionPayloadHeader.default())
  end

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
  @spec get_flag_index_deltas(t(), integer(), integer()) ::
          Enumerable.t({SszTypes.gwei(), SszTypes.gwei()})
  def get_flag_index_deltas(state, weight, flag_index) do
    previous_epoch = Accessors.get_previous_epoch(state)

    {:ok, unslashed_participating_indices} =
      Accessors.get_unslashed_participating_indices(state, flag_index, previous_epoch)

    unslashed_participating_balance =
      Accessors.get_total_balance(state, unslashed_participating_indices)

    effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")

    unslashed_participating_increments =
      div(unslashed_participating_balance, effective_balance_increment)

    active_increments =
      div(Accessors.get_total_active_balance(state), effective_balance_increment)

    weight_denominator = Constants.weight_denominator()

    previous_epoch = Accessors.get_previous_epoch(state)

    state.validators
    |> Stream.with_index()
    |> Stream.map(fn {validator, index} ->
      if Predicates.is_eligible_validator(validator, previous_epoch) do
        base_reward = Accessors.get_base_reward(state, index)
        is_unslashed = MapSet.member?(unslashed_participating_indices, index)

        cond do
          is_unslashed and Predicates.is_in_inactivity_leak(state) ->
            {0, 0}

          is_unslashed ->
            reward_numerator = base_reward * weight * unslashed_participating_increments
            reward = div(reward_numerator, active_increments * weight_denominator)
            {reward, 0}

          flag_index != Constants.timely_head_flag_index() ->
            penalty = div(base_reward * weight, weight_denominator)
            {0, penalty}

          true ->
            {0, 0}
        end
      else
        {0, 0}
      end
    end)
  end

  @doc """
  Return the inactivity penalty deltas by considering timely
  target participation flags and inactivity scores.
  """
  @spec get_inactivity_penalty_deltas(t()) :: {list(SszTypes.gwei()), list(SszTypes.gwei())}
  def get_inactivity_penalty_deltas(state) do
    previous_epoch = Accessors.get_previous_epoch(state)

    {:ok, matching_target_indices} =
      Accessors.get_unslashed_participating_indices(
        state,
        Constants.timely_target_flag_index(),
        previous_epoch
      )

    penalty_denominator =
      ChainSpec.get("INACTIVITY_SCORE_BIAS") *
        ChainSpec.get("INACTIVITY_PENALTY_QUOTIENT_BELLATRIX")

    state.validators
    |> Stream.zip(state.inactivity_scores)
    |> Stream.with_index()
    |> Stream.map(fn {{validator, inactivity_score}, index} ->
      if Predicates.is_eligible_validator(validator, previous_epoch) and
           not MapSet.member?(matching_target_indices, index) do
        penalty_numerator = validator.effective_balance * inactivity_score
        penalty = div(penalty_numerator, penalty_denominator)
        {0, penalty}
      else
        {0, 0}
      end
    end)
  end
end
