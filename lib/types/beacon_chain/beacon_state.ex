defmodule Types.BeaconState do
  @moduledoc """
  Struct definition for `BeaconState`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  use LambdaEthereumConsensus.Container

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.Utils.BitVector
  alias Types.ExecutionPayloadHeader

  require HardForkAliasInjection

  # Fulu (EIP-7917) adds proposer_lookahead
  fulu_fields =
    if Application.compile_env!(:lambda_ethereum_consensus, :fork) == :fulu,
      do: [:proposer_lookahead],
      else: []

  fields =
    [
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
      :historical_summaries,
      # New Electra fields
      :deposit_requests_start_index,
      :deposit_balance_to_consume,
      :exit_balance_to_consume,
      :earliest_exit_epoch,
      :consolidation_balance_to_consume,
      :earliest_consolidation_epoch,
      :pending_deposits,
      :pending_partial_withdrawals,
      :pending_consolidations
    ] ++ fulu_fields

  @enforce_keys fields
  defstruct fields

  if Application.compile_env!(:lambda_ethereum_consensus, :fork) == :fulu do
    @type t :: %__MODULE__{
            genesis_time: Types.uint64(),
            genesis_validators_root: Types.root(),
            slot: Types.slot(),
            fork: Types.Fork.t(),
            latest_block_header: Types.BeaconBlockHeader.t(),
            block_roots: list(Types.root()),
            state_roots: list(Types.root()),
            historical_roots: list(Types.root()),
            eth1_data: Types.Eth1Data.t(),
            eth1_data_votes: list(Types.Eth1Data.t()),
            eth1_deposit_index: Types.uint64(),
            validators: Aja.Vector.t(Types.Validator.t()),
            balances: Aja.Vector.t(Types.gwei()),
            randao_mixes: Aja.Vector.t(Types.bytes32()),
            slashings: list(Types.gwei()),
            previous_epoch_participation: Aja.Vector.t(Types.participation_flags()),
            current_epoch_participation: Aja.Vector.t(Types.participation_flags()),
            justification_bits: BitVector.t(),
            previous_justified_checkpoint: Types.Checkpoint.t(),
            current_justified_checkpoint: Types.Checkpoint.t(),
            finalized_checkpoint: Types.Checkpoint.t(),
            inactivity_scores: list(Types.uint64()),
            current_sync_committee: Types.SyncCommittee.t(),
            next_sync_committee: Types.SyncCommittee.t(),
            latest_execution_payload_header: ExecutionPayloadHeader.t(),
            next_withdrawal_index: Types.withdrawal_index(),
            next_withdrawal_validator_index: Types.withdrawal_index(),
            historical_summaries: list(Types.HistoricalSummary.t()),
            deposit_requests_start_index: Types.uint64(),
            deposit_balance_to_consume: Types.gwei(),
            exit_balance_to_consume: Types.gwei(),
            earliest_exit_epoch: Types.epoch(),
            consolidation_balance_to_consume: Types.gwei(),
            earliest_consolidation_epoch: Types.epoch(),
            pending_deposits: list(Types.PendingDeposit.t()),
            pending_partial_withdrawals: list(Types.PendingPartialWithdrawal.t()),
            pending_consolidations: list(Types.PendingConsolidation.t()),
            # [New in Fulu:EIP7917]
            proposer_lookahead: list(Types.validator_index())
          }
  else
    @type t :: %__MODULE__{
            genesis_time: Types.uint64(),
            genesis_validators_root: Types.root(),
            slot: Types.slot(),
            fork: Types.Fork.t(),
            latest_block_header: Types.BeaconBlockHeader.t(),
            block_roots: list(Types.root()),
            state_roots: list(Types.root()),
            historical_roots: list(Types.root()),
            eth1_data: Types.Eth1Data.t(),
            eth1_data_votes: list(Types.Eth1Data.t()),
            eth1_deposit_index: Types.uint64(),
            validators: Aja.Vector.t(Types.Validator.t()),
            balances: Aja.Vector.t(Types.gwei()),
            randao_mixes: Aja.Vector.t(Types.bytes32()),
            slashings: list(Types.gwei()),
            previous_epoch_participation: Aja.Vector.t(Types.participation_flags()),
            current_epoch_participation: Aja.Vector.t(Types.participation_flags()),
            justification_bits: BitVector.t(),
            previous_justified_checkpoint: Types.Checkpoint.t(),
            current_justified_checkpoint: Types.Checkpoint.t(),
            finalized_checkpoint: Types.Checkpoint.t(),
            inactivity_scores: list(Types.uint64()),
            current_sync_committee: Types.SyncCommittee.t(),
            next_sync_committee: Types.SyncCommittee.t(),
            latest_execution_payload_header: ExecutionPayloadHeader.t(),
            next_withdrawal_index: Types.withdrawal_index(),
            next_withdrawal_validator_index: Types.withdrawal_index(),
            historical_summaries: list(Types.HistoricalSummary.t()),
            deposit_requests_start_index: Types.uint64(),
            deposit_balance_to_consume: Types.gwei(),
            exit_balance_to_consume: Types.gwei(),
            earliest_exit_epoch: Types.epoch(),
            consolidation_balance_to_consume: Types.gwei(),
            earliest_consolidation_epoch: Types.epoch(),
            pending_deposits: list(Types.PendingDeposit.t()),
            pending_partial_withdrawals: list(Types.PendingPartialWithdrawal.t()),
            pending_consolidations: list(Types.PendingConsolidation.t())
          }
  end

  @impl LambdaEthereumConsensus.Container
  def schema() do
    base = [
      {:genesis_time, TypeAliases.uint64()},
      {:genesis_validators_root, TypeAliases.root()},
      {:slot, TypeAliases.slot()},
      {:fork, Types.Fork},
      {:latest_block_header, Types.BeaconBlockHeader},
      {:block_roots, {:vector, TypeAliases.root(), ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")}},
      {:state_roots, {:vector, TypeAliases.root(), ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")}},
      {:historical_roots, {:list, TypeAliases.root(), ChainSpec.get("HISTORICAL_ROOTS_LIMIT")}},
      {:eth1_data, Types.Eth1Data},
      {:eth1_data_votes,
       {:list, Types.Eth1Data,
        ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD") * ChainSpec.get("SLOTS_PER_EPOCH")}},
      {:eth1_deposit_index, TypeAliases.uint64()},
      {:validators, {:list, Types.Validator, ChainSpec.get("VALIDATOR_REGISTRY_LIMIT")}},
      {:balances, {:list, TypeAliases.gwei(), ChainSpec.get("VALIDATOR_REGISTRY_LIMIT")}},
      {:randao_mixes,
       {:vector, TypeAliases.bytes32(), ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")}},
      {:slashings, {:vector, TypeAliases.gwei(), ChainSpec.get("EPOCHS_PER_SLASHINGS_VECTOR")}},
      {:previous_epoch_participation,
       {:list, TypeAliases.participation_flags(), ChainSpec.get("VALIDATOR_REGISTRY_LIMIT")}},
      {:current_epoch_participation,
       {:list, TypeAliases.participation_flags(), ChainSpec.get("VALIDATOR_REGISTRY_LIMIT")}},
      {:justification_bits, {:bitvector, Constants.justification_bits_length()}},
      {:previous_justified_checkpoint, Types.Checkpoint},
      {:current_justified_checkpoint, Types.Checkpoint},
      {:finalized_checkpoint, Types.Checkpoint},
      {:inactivity_scores,
       {:list, TypeAliases.uint64(), ChainSpec.get("VALIDATOR_REGISTRY_LIMIT")}},
      {:current_sync_committee, Types.SyncCommittee},
      {:next_sync_committee, Types.SyncCommittee},
      {:latest_execution_payload_header, ExecutionPayloadHeader},
      {:next_withdrawal_index, TypeAliases.withdrawal_index()},
      {:next_withdrawal_validator_index, TypeAliases.validator_index()},
      {:historical_summaries,
       {:list, Types.HistoricalSummary, ChainSpec.get("HISTORICAL_ROOTS_LIMIT")}},
      # New Electra fields
      {:deposit_requests_start_index, TypeAliases.uint64()},
      {:deposit_balance_to_consume, TypeAliases.gwei()},
      {:exit_balance_to_consume, TypeAliases.gwei()},
      {:earliest_exit_epoch, TypeAliases.epoch()},
      {:consolidation_balance_to_consume, TypeAliases.gwei()},
      {:earliest_consolidation_epoch, TypeAliases.epoch()},
      {:pending_deposits, {:list, Types.PendingDeposit, ChainSpec.get("PENDING_DEPOSITS_LIMIT")}},
      {:pending_partial_withdrawals,
       {:list, Types.PendingPartialWithdrawal, ChainSpec.get("PENDING_PARTIAL_WITHDRAWALS_LIMIT")}},
      {:pending_consolidations,
       {:list, Types.PendingConsolidation, ChainSpec.get("PENDING_CONSOLIDATIONS_LIMIT")}}
    ]

    if HardForkAliasInjection.fulu?() do
      base ++
        [
          # New Fulu fields (EIP-7917)
          {:proposer_lookahead,
           {:vector, TypeAliases.validator_index(), 2 * ChainSpec.get("SLOTS_PER_EPOCH")}}
        ]
    else
      base
    end
  end

  def encode(%__MODULE__{} = map) do
    map
    |> Map.update!(:validators, &Aja.Vector.to_list/1)
    |> Map.update!(:balances, &Aja.Vector.to_list/1)
    |> Map.update!(:randao_mixes, &Aja.Vector.to_list/1)
    |> Map.update!(:previous_epoch_participation, &Aja.Vector.to_list/1)
    |> Map.update!(:current_epoch_participation, &Aja.Vector.to_list/1)
    |> Map.update!(:latest_execution_payload_header, &ExecutionPayloadHeader.encode/1)
    |> Map.update!(:justification_bits, &BitVector.to_bytes/1)
  end

  def decode(%__MODULE__{} = map) do
    map
    |> Map.update!(:validators, &Aja.Vector.new/1)
    |> Map.update!(:balances, &Aja.Vector.new/1)
    |> Map.update!(:randao_mixes, &Aja.Vector.new/1)
    |> Map.update!(:previous_epoch_participation, &Aja.Vector.new/1)
    |> Map.update!(:current_epoch_participation, &Aja.Vector.new/1)
    |> Map.update!(:latest_execution_payload_header, &ExecutionPayloadHeader.decode/1)
    |> Map.update!(:justification_bits, fn bits ->
      BitVector.new(bits, Constants.justification_bits_length())
    end)
  end

  def decode_ex(%__MODULE__{} = map) do
    map
    |> Map.update!(:validators, &Aja.Vector.new/1)
    |> Map.update!(:balances, &Aja.Vector.new/1)
    |> Map.update!(:randao_mixes, &Aja.Vector.new/1)
    |> Map.update!(:previous_epoch_participation, &Aja.Vector.new/1)
    |> Map.update!(:current_epoch_participation, &Aja.Vector.new/1)
  end

  @doc """
  Checks if state is pre or post merge
  """
  @spec merge_transition_complete?(t()) :: boolean()
  def merge_transition_complete?(state) do
    state.latest_execution_payload_header !=
      struct(Types.ExecutionPayload, ExecutionPayloadHeader.default())
  end

  @doc """
      Decrease the validator balance at index ``index`` by ``delta``, with underflow protection.
  """
  @spec decrease_balance(t(), Types.validator_index(), Types.gwei()) :: t()
  def decrease_balance(%__MODULE__{balances: balances} = state, index, delta) do
    %{state | balances: Aja.Vector.update_at!(balances, index, &max(&1 - delta, 0))}
  end

  @doc """
    Increase the validator balance at index ``index`` by ``delta``.
  """
  @spec increase_balance(t(), Types.validator_index(), Types.gwei()) :: t()
  def increase_balance(%__MODULE__{balances: balances} = state, index, delta) do
    %{state | balances: Aja.Vector.update_at!(balances, index, &(&1 + delta))}
  end

  @doc """
  Return the deltas for a given ``flag_index`` by scanning through the participation flags.
  """
  @spec get_flag_index_deltas(t(), integer(), integer(), MapSet.t(), Types.gwei()) ::
          Enumerable.t({Types.gwei(), Types.gwei()})
  def get_flag_index_deltas(
        state,
        weight,
        flag_index,
        unslashed_participating_indices,
        base_reward_per_increment
      ) do
    previous_epoch = Accessors.get_previous_epoch(state)

    unslashed_participating_balance =
      Accessors.get_total_balance(state, unslashed_participating_indices)

    effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")

    unslashed_participating_increments =
      div(unslashed_participating_balance, effective_balance_increment)

    active_increments =
      div(Accessors.get_total_active_balance(state), effective_balance_increment)

    weight_denominator = Constants.weight_denominator()
    in_inactivity_leak? = Predicates.in_inactivity_leak?(state)
    timely_head_flag_index = Constants.timely_head_flag_index()

    ctx =
      {weight, flag_index, effective_balance_increment, base_reward_per_increment,
       unslashed_participating_increments, active_increments, weight_denominator,
       in_inactivity_leak?, timely_head_flag_index, previous_epoch,
       unslashed_participating_indices}

    state.validators
    |> Stream.with_index()
    |> Stream.map(&compute_flag_delta(&1, ctx))
  end

  defp compute_flag_delta(
         {validator, index},
         {weight, flag_index, ebi, brpi, upi, ai, wd, in_leak?, thfi, prev_epoch, indices}
       ) do
    if Predicates.eligible_validator?(validator, prev_epoch) do
      base_reward = div(validator.effective_balance, ebi) * brpi
      is_unslashed = MapSet.member?(indices, index)

      cond do
        is_unslashed and in_leak? -> 0
        is_unslashed -> div(base_reward * weight * upi, ai * wd)
        flag_index != thfi -> -div(base_reward * weight, wd)
        true -> 0
      end
    else
      0
    end
  end

  @doc """
  Return the inactivity penalty deltas by considering timely
  target participation flags and inactivity scores.
  """
  @spec get_inactivity_penalty_deltas(t(), MapSet.t()) ::
          Enumerable.t({Types.gwei(), Types.gwei()})
  def get_inactivity_penalty_deltas(%__MODULE__{} = state, matching_target_indices) do
    previous_epoch = Accessors.get_previous_epoch(state)

    penalty_denominator =
      ChainSpec.get("INACTIVITY_SCORE_BIAS") *
        ChainSpec.get("INACTIVITY_PENALTY_QUOTIENT_BELLATRIX")

    state.validators
    |> Stream.zip(state.inactivity_scores)
    |> Stream.with_index()
    |> Stream.map(fn {{validator, inactivity_score}, index} ->
      if Predicates.eligible_validator?(validator, previous_epoch) and
           not MapSet.member?(matching_target_indices, index) do
        penalty_numerator = validator.effective_balance * inactivity_score
        -div(penalty_numerator, penalty_denominator)
      else
        0
      end
    end)
  end
end
