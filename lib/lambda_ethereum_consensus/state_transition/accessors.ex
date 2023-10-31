defmodule LambdaEthereumConsensus.StateTransition.Accessors do
  @moduledoc """
  Functions accessing the current beacon state
  """
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState

  @doc """
  Return the sequence of active validator indices at ``epoch``.
  """
  @spec get_active_validator_indices(BeaconState.t(), SszTypes.epoch()) ::
          list(SszTypes.validator_index())
  def get_active_validator_indices(%BeaconState{validators: validators} = _state, epoch) do
    validators
    |> Stream.with_index()
    |> Stream.filter(fn {v, _} ->
      Predicates.is_active_validator(v, epoch)
    end)
    |> Stream.map(fn {_, index} -> index end)
    |> Enum.to_list()
  end

  @doc """
  Return the current epoch.
  """
  @spec get_current_epoch(BeaconState.t()) :: SszTypes.epoch()
  def get_current_epoch(%BeaconState{slot: slot} = _state) do
    Misc.compute_epoch_at_slot(slot)
  end

  @doc """
  Return the previous epoch (unless the current epoch is ``GENESIS_EPOCH``).
  """
  @spec get_previous_epoch(BeaconState.t()) :: SszTypes.epoch()
  def get_previous_epoch(%BeaconState{} = state) do
    current_epoch = get_current_epoch(state)
    genesis_epoch = Constants.genesis_epoch()

    if current_epoch == genesis_epoch do
      genesis_epoch
    else
      current_epoch - 1
    end
  end

  @doc """
  Return the set of validator indices that are both active and unslashed for the given ``flag_index`` and ``epoch``.
  """
  @spec get_unslashed_participating_indices(BeaconState.t(), integer, SszTypes.epoch()) ::
          {:ok, MapSet.t()} | {:error, binary()}
  def get_unslashed_participating_indices(%BeaconState{} = state, flag_index, epoch) do
    if epoch in [get_previous_epoch(state), get_current_epoch(state)] do
      epoch_participation =
        if epoch == get_current_epoch(state) do
          state.current_epoch_participation
        else
          state.previous_epoch_participation
        end

      active_validator_indices = get_active_validator_indices(state, epoch)

      participating_indices =
        active_validator_indices
        |> Stream.filter(fn index ->
          current_epoch_participation = Enum.at(epoch_participation, index)
          Predicates.has_flag(current_epoch_participation, flag_index)
        end)
        |> Stream.filter(fn index ->
          validator = Enum.at(state.validators, index)
          not validator.slashed
        end)

      {:ok, MapSet.new(participating_indices)}
    else
      {:error, "epoch is not present in get_current_epoch or get_previous_epoch of the state"}
    end
  end

  @doc """
  Return the randao mix at a recent ``epoch``.
  """
  @spec get_randao_mix(BeaconState.t(), SszTypes.epoch()) :: SszTypes.bytes32()
  def get_randao_mix(%BeaconState{randao_mixes: randao_mixes}, epoch) do
    epochs_per_historical_vector = ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")
    Enum.fetch!(randao_mixes, rem(epoch, epochs_per_historical_vector))
  end

  @doc """
  Return the validator churn limit for the current epoch.
  """
  @spec get_validator_churn_limit(BeaconState.t()) :: SszTypes.uint64()
  def get_validator_churn_limit(%BeaconState{} = state) do
    active_validator_indices = get_active_validator_indices(state, get_current_epoch(state))
    min_per_epoch_churn_limit = ChainSpec.get("MIN_PER_EPOCH_CHURN_LIMIT")
    churn_limit_quotient = ChainSpec.get("CHURN_LIMIT_QUOTIENT")
    max(min_per_epoch_churn_limit, div(length(active_validator_indices), churn_limit_quotient))
  end

  @doc """
  Returns the number of epochs since the last finalised checkpoint (minus one).
  """
  @spec get_finality_delay(BeaconState.t()) :: SszTypes.uint64()
  def get_finality_delay(%BeaconState{} = state) do
    get_previous_epoch(state) - state.finalized_checkpoint.epoch
  end

  @doc """
  These are the validators that were subject to rewards and penalties in the previous epoch.
  """
  @spec get_eligible_validator_indices(BeaconState.t()) :: list(SszTypes.validator_index())
  def get_eligible_validator_indices(%BeaconState{validators: validators} = state) do
    previous_epoch = get_previous_epoch(state)

    validators
    |> Stream.with_index()
    |> Stream.filter(fn {validator, _index} ->
      Predicates.is_active_validator(validator, previous_epoch) ||
        (validator.slashed && previous_epoch + 1 < validator.withdrawable_epoch)
    end)
    |> Stream.map(fn {_validator, index} -> index end)
    |> Enum.to_list()
  end

  @doc """
  Return the combined effective balance of the active validators.
  Note: ``get_total_balance`` returns ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
  """
  @spec get_total_active_balance(BeaconState.t()) :: SszTypes.gwei()
  def get_total_active_balance(state) do
    get_total_balance(state, get_active_validator_indices(state, get_current_epoch(state)))
  end

  @doc """
  Return the combined effective balance of the ``indices``.
  ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
  Math safe up to ~10B ETH, after which this overflows uint64.
  """
  @spec get_total_balance(BeaconState.t(), list(SszTypes.validator_index())) :: SszTypes.gwei()
  def get_total_balance(state, indices) do
    max(
      ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT"),
      Enum.sum(
        Enum.map(indices, fn index -> Enum.at(state.validators, index).effective_balance end)
      )
    )
  end

  @doc """
  Return the block root at the start of a recent ``epoch``.
  """

  @spec get_block_root(BeaconState.t(), SszTypes.epoch()) :: SszTypes.root()
  def get_block_root(state, epoch) do
    get_block_root_at_slot(state, Misc.compute_start_slot_at_epoch(epoch))
  end

  @doc """
  Return the block root at a recent ``slot``
  """
  @spec get_block_root_at_slot(BeaconState.t(), SszTypes.slot()) ::
          {:ok, SszTypes.root()} | {:error, binary()}
  def get_block_root_at_slot(state, slot) do
    slots_per_root = ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")

    if slot < state.slot and state.slot <= slot + slots_per_root do
      root = Enum.at(state.block_roots, rem(slot, slots_per_root))
      {:ok, root}
    else
      {:error, "slot older than the SLOTS_PER_HISTsORICAL_ROOT limit"}
    end
  end
end

# <!-- @doc """
# """
# @spec get_unslashed_attesting_indices(BeaconState.t(), set(list(PendingAttestation.t()))) :: list(SszTypes.validator_index())
# def get_unslashed_attesting_indices(state, attestations) do
#     output = set()

#     Enum.map(attestations, fn a -> get_attesting_indices(state, a.data, a.aggregation_bits))

#     for a in attestations:
#         output = output.union(get_attesting_indices(state, a.data, a.aggregation_bits))
#     return set(filter(lambda index: not state.validators[index].slashed, output))
# end -->

# @doc """
# Return the set of attesting indices corresponding to ``data`` and ``bits``.
# """
# @spec get_attesting_indices(BeaconState.t(), SszTypes.AttestationData.t(), SszTypes.bitlist()) ::
#         SszTypes.list(SszTypes.validator_index())
# def get_attesting_indices(state, data, bits) do
#   committee = get_beacon_committee(state, data.slot, data.index)

#   committee
#   |> Stream.with_index()
#   |> Stream.filter(fn {i, index} -> bits[i] end)
#   |> Stream.map(fn {_validator, index} -> index end)
#   # |> Stream.uniq()
#   |> Enum.to_list()
# end

# @doc """
# Return the beacon committee at ``slot`` for ``index``.
# """

# @spec get_beacon_committee(BeaconState.t(), SszTypes.slot(), SszTypes.commitee_index()) :: list(SszTypes.validator_index())
# def get_beacon_committee(state, slot, index) do
#     epoch = Misc.compute_epoch_at_slot(slot)
#     committees_per_slot = get_committee_count_per_slot(state, epoch)
#     return Misc.compute_committee(
#         indices=get_active_validator_indices(state, epoch),
#         seed=get_seed(state, epoch, DOMAIN_BEACON_ATTESTER),
#         index=(slot % \\SLOTS_PER_EPOCH) * committees_per_slot + index,
#         count=committees_per_slot * SLOTS_PER_EPOCH,
#     )
# end

# @doc """
# Return the number of committees in each slot for the given ``epoch``.
# """

# @spec get_committee_count_per_slot(BeaconState.t(), SszTypes.epoch()) :: SszTypes.uint64()
# def get_committee_count_per_slot(state, epoch) do
#   active_validator_indices = get_active_validator_indices(state, epoch)
#   committee_count = div(length(active_validator_indices), SLOTS_PER_EPOCH * TARGET_COMMITTEE_SIZE)
#   committee_count = max(1, min(committee_count, MAX_COMMITTEES_PER_SLOT))
#   committee_count
# end

# @doc """
# Return the seed at ``epoch``.
# """

# @spec get_seed(BeaconState.t(), SszTypes.epoch(), SszTypes.domain_type()) :: SszTypes.bytes32()
# def get_seed(state, epoch, domain_type) do
#   # Avoid underflow
#   mix =
#     get_randao_mix(
#       state,
#       epoch + ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR") - ChainSpec.get("MIN_SEED_LOOKAHEAD") -
#         1
#     )

#   seed = :crypto.hash(:sha256, domain_type + <<epoch::256-little-unsigned>> + mix)
#   seed
# end

# end
