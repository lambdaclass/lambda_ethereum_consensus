defmodule SszTypes.BeaconState do
  @moduledoc """
  Struct definition for `BeaconState`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

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
          # size SLOTS_PER_HISTORICAL_ROOT 8192
          block_roots: list(SszTypes.root()),
          # size SLOTS_PER_HISTORICAL_ROOT 8192
          state_roots: list(SszTypes.root()),
          # Frozen in Capella, replaced by historical_summaries
          # size HISTORICAL_ROOTS_LIMIT 16777216
          historical_roots: list(SszTypes.root()),
          # Eth1
          eth1_data: SszTypes.Eth1Data.t(),
          # size EPOCHS_PER_ETH1_VOTING_PERIOD (64) * SLOTS_PER_EPOCH (32) = 2048
          eth1_data_votes: list(SszTypes.Eth1Data.t()),
          eth1_deposit_index: SszTypes.uint64(),
          # Registry
          # size VALIDATOR_REGISTRY_LIMIT 1099511627776
          validators: list(SszTypes.Validator.t()),
          # size VALIDATOR_REGISTRY_LIMIT 1099511627776
          balances: list(SszTypes.gwei()),
          # Randomness
          # size EPOCHS_PER_HISTORICAL_VECTOR 65_536
          randao_mixes: list(SszTypes.bytes32()),
          # Slashings
          # Per-epoch sums of slashed effective balances
          # size EPOCHS_PER_SLASHINGS_VECTOR 8192
          slashings: list(SszTypes.gwei()),
          # Participation
          # size VALIDATOR_REGISTRY_LIMIT 1099511627776
          previous_epoch_participation: list(SszTypes.participation_flags()),
          # size VALIDATOR_REGISTRY_LIMIT 1099511627776
          current_epoch_participation: list(SszTypes.participation_flags()),
          # Finality
          # Bit set for every recent justified epoch size 4
          justification_bits: SszTypes.bitvector(),
          previous_justified_checkpoint: SszTypes.Checkpoint.t(),
          current_justified_checkpoint: SszTypes.Checkpoint.t(),
          finalized_checkpoint: SszTypes.Checkpoint.t(),
          # Inactivity
          # size VALIDATOR_REGISTRY_LIMIT 1099511627776
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
          # size HISTORICAL_ROOTS_LIMIT 16777216
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

    process_reward_and_penalty = fn index ->
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
    end

    state.validators
    |> Stream.with_index()
    |> Stream.map(fn {validator, index} ->
      if Predicates.is_eligible_validator(validator, previous_epoch) do
        process_reward_and_penalty.(index)
      else
        {0, 0}
      end
    end)
  end

  @doc """
  Return the inactivity penalty deltas by considering timely
  target participation flags and inactivity scores.
  """
  @spec get_inactivity_penalty_deltas(t()) :: Enumerable.t({SszTypes.gwei(), SszTypes.gwei()})
  def get_inactivity_penalty_deltas(%__MODULE__{} = state) do
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

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:genesis_time, {:int, 64}},
      {:genesis_validators_root, {:bytes, 32}},
      {:slot, {:int, 64}},
      {:fork, SszTypes.Fork},
      {:latest_block_header, SszTypes.BeaconBlockHeader},
      {:block_roots, {:list, {:bytes, 32}, 8192}},
      {:state_roots, {:list, {:bytes, 32}, 8192}},
      {:historical_roots, {:list, {:bytes, 32}, 16_777_216}},
      {:eth1_data, SszTypes.Eth1Data},
      {:eth1_data_votes, {:list, SszTypes.Eth1Data, 2048}},
      {:eth1_deposit_index, {:int, 64}},
      {:validators, {:list, SszTypes.Validator, 1_099_511_627_776}},
      {:balances, {:list, {:int, 64}, 1_099_511_627_776}},
      {:randao_mixes, {:list, {:bytes, 32}, 65_536}},
      {:slashings, {:list, {:int, 64}, 8192}},
      {:previous_epoch_participation, {:list, {:int, 8}, 1_099_511_627_776}},
      {:current_epoch_participation, {:list, {:int, 8}, 1_099_511_627_776}},
      {:justification_bits, {:bitvector, 4}},
      {:previous_justified_checkpoint, SszTypes.Checkpoint},
      {:current_justified_checkpoint, SszTypes.Checkpoint},
      {:finalized_checkpoint, SszTypes.Checkpoint},
      {:inactivity_scores, {:list, {:int, 64}, 1_099_511_627_776}},
      {:current_sync_committee, SszTypes.SyncCommittee},
      {:next_sync_committee, SszTypes.SyncCommittee},
      {:latest_execution_payload_header, SszTypes.ExecutionPayloadHeader},
      {:next_withdrawal_index, {:int, 64}},
      {:next_withdrawal_validator_index, {:int, 64}},
      {:historical_summaries, {:list, SszTypes.HistoricalSummary, 16_777_216}}
    ]
  end
end
