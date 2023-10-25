defmodule LambdaEthereumConsensus.StateTransition.Accessors do
  @moduledoc """
  Functions accessing the current beacon state
  """
  alias LambdaEthereumConsensus.StateTransition.Math
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState
  alias SszTypes.Attestation
  alias SszTypes.IndexedAttestation

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
  Return the number of committees in each slot for the given ``epoch``.
  """
  @spec get_committee_count_per_slot(BeaconState.t(), SszTypes.epoch()) :: SszTypes.uint64()
  def get_committee_count_per_slot(state, epoch) do
    active_validators_count = length(get_active_validator_indices(state, epoch))

    committee_size =
      active_validators_count
      |> Kernel.div(ChainSpec.get("SLOTS_PER_EPOCH"))
      |> Kernel.div(ChainSpec.get("TARGET_COMMITTEE_SIZE"))

    [ChainSpec.get("MAX_COMMITTEES_PER_SLOT"), committee_size]
    |> Enum.min()
    |> (&max(1, &1)).()
  end

  @doc """
  Return the beacon committee at ``slot`` for ``index``.
  """
  @spec get_beacon_committee(BeaconState.t(), SszTypes.slot(), SszTypes.committee_index()) ::
          list(SszTypes.validator_index())
  def get_beacon_committee(state, slot, index) do
    epoch = Misc.compute_epoch_at_slot(slot)
    committees_per_slot = get_committee_count_per_slot(state, epoch)

    Misc.compute_committee(
      get_active_validator_indices(state, epoch),
      get_seed(state, epoch, Constants.domain_beacon_attester()),
      rem(slot, ChainSpec.get("SLOTS_PER_EPOCH")) * committees_per_slot + index,
      committees_per_slot * ChainSpec.get("SLOTS_PER_EPOCH")
    )
  end

  @spec get_base_reward_per_increment(BeaconState.t()) :: SszTypes.gwei()
  def get_base_reward_per_increment(state) do
    numerator = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT") * Constants.base_reward_factor()
    denominator = Math.integer_squareroot(get_total_active_balance(state))
    div(numerator, denominator)
  end

  @doc """
  Return the base reward for the validator defined by ``index`` with respect to the current ``state``.
  """
  @spec get_base_reward(BeaconState.t(), SszTypes.validator_index()) :: SszTypes.gwei()
  def get_base_reward(state, index) do
    validator = Enum.at(state.validators, index)
    effective_balance = validator.effective_balance

    increments =
      div(
        effective_balance,
        ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")
      )

    increments * get_base_reward_per_increment(state)
  end

  @doc """
  Return the flag indices that are satisfied by an attestation.
  """
  @spec get_attestation_participation_flag_indices(
          BeaconState.t(),
          SszTypes.AttestationData.t(),
          SszTypes.uint64()
        ) ::
          {:ok, list(SszTypes.uint64())} | {:error, binary()}
  def get_attestation_participation_flag_indices(state, data, inclusion_delay) do
    justified_checkpoint =
      if data.target.epoch == get_current_epoch(state) do
        state.current_justified_checkpoint
      else
        state.previous_justified_checkpoint
      end

    block_root = get_block_root(state, data.target.epoch)
    {:ok, block_root_at_slot} = get_block_root_at_slot(state, data.slot)

    # Matching roots
    is_matching_source = data.source == justified_checkpoint

    is_matching_target =
      is_matching_source && data.target.root == block_root

    is_matching_head =
      is_matching_target && data.beacon_block_root == block_root_at_slot

    if not is_matching_source do
      {:error, "Attestation source does not match justified checkpoint"}
    end

    source_indices =
      if is_matching_source &&
           inclusion_delay <= Math.integer_squareroot(ChainSpec.get("SLOTS_PER_EPOCH")) do
        [Constants.timely_source_flag_index()]
      else
        []
      end

    target_indices =
      if is_matching_target && inclusion_delay <= ChainSpec.get("SLOTS_PER_EPOCH") do
        [Constants.timely_target_flag_index()]
      else
        []
      end

    head_indices =
      if is_matching_head && inclusion_delay == ChainSpec.get(MIN_ATTESTATION_INCLUSION_DELAY) do
        [Constants.timely_head_flag_index()]
      else
        []
      end

    {:ok, source_indices ++ target_indices ++ head_indices}
  end

  @doc """
  Return the block root at a recent ``slot``.
  """
  @spec get_block_root_at_slot(BeaconState.t(), SszTypes.slot()) ::
          {:ok, SszTypes.root()} | {:error, binary()}
  def get_block_root_at_slot(state, slot) do
    if slot < state.slot && state.slot <= slot + ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT") do
      root = Enum.fetch!(state.block_roots, rem(slot, ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")))
      {:ok, root}
    else
      {:error, "Block root not available"}
    end
  end

  @doc """
  Return the block root at the start of a recent ``epoch``.
  """
  @spec get_block_root(BeaconState.t(), SszTypes.epoch()) :: SszTypes.root()
  def get_block_root(state, epoch) do
    {:ok, block_root} = get_block_root_at_slot(state, Misc.compute_start_slot_at_epoch(epoch))
    block_root
  end

  @doc """
  Return the seed at ``epoch``.
  """
  @spec get_seed(BeaconState.t(), SszTypes.epoch(), SszTypes.domain_type()) :: SszTypes.bytes32()
  def get_seed(state, epoch, domain_type) do
    mix =
      get_randao_mix(
        state,
        epoch + ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR") -
          ChainSpec.get("MIN_SEED_LOOKAHEAD") - 1
      )

    :crypto.hash(:sha256, domain_type <> Misc.uint64_to_bytes(epoch) <> mix)
  end

  @doc """
  Return the signature domain (fork version concatenated with domain type) of a message.
  """
  @spec get_domain(BeaconState.t(), SszTypes.domain_type(), SszTypes.epoch()) :: SszTypes.domain()
  def get_domain(state, domain_type, epoch) do
    epoch = if epoch == nil, do: get_current_epoch(state), else: epoch

    fork_version =
      if epoch < state.fork.epoch do
        state.fork.previous_version
      else
        state.fork.current_version
      end

    Misc.compute_domain(domain_type, fork_version, state.genesis_validators_root)
  end

  @doc """
  Return the indexed attestation corresponding to ``attestation``.
  """
  @spec get_indexed_attestation(BeaconState.t(), Attestation.t()) :: IndexedAttestation.t()
  def get_indexed_attestation(state, attestation) do
    attesting_indices =
      get_attesting_indices(state, attestation.data, attestation.aggregation_bits)

    sorted_attesting_indices = Enum.sort(attesting_indices)
    {sorted_attesting_indices, attestation, attestation.signature}
  end

  @doc """
  Return the set of attesting indices corresponding to ``data`` and ``bits``.
  """
  @spec get_attesting_indices(BeaconState.t(), SszTypes.AttestationData.t(), SszTypes.bitlist()) ::
          MapSet.t()
  def get_attesting_indices(state, data, bits) do
    committee = get_beacon_committee(state, data.slot, data.index)
    bit_list = bitstring_to_list(bits)

    committee
    |> Stream.with_index()
    |> Stream.filter(fn {_, i} -> Enum.at(bit_list, i) end)
    |> Stream.map(fn {index, _i} -> index end)
    |> MapSet.new()
  end

  defp bitstring_to_list(<<bit::1, rest::bitstring>>), do: [bit | bitstring_to_list(rest)]
  defp bitstring_to_list(<<>>), do: []

  @doc """
  Return the beacon proposer index at the current slot.
  """
  @spec get_beacon_proposer_index(BeaconState.t()) :: SszTypes.validator_index()
  def get_beacon_proposer_index(state) do
    epoch = get_current_epoch(state)

    seed =
      :crypto.hash(
        :sha256,
        get_seed(state, epoch, Constants.domain_beacon_proposer()) <>
          Misc.uint64_to_bytes(state.slot)
      )

    indices = get_active_validator_indices(state, epoch)
    Misc.compute_proposer_index(state, indices, seed)
  end

  @doc """
  Return the combined effective balance of the ``indices``.
  ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
  Math safe up to ~10B ETH, after which this overflows uint64.
  """
  @spec get_total_balance(BeaconState.t(), list(SszTypes.validator_index())) :: SszTypes.gwei()
  def get_total_balance(state, indices) do
    total_balance =
      indices
      |> Enum.map(fn index -> Map.get(Enum.at(state.validators, index), :effective_balance, 0) end)
      |> Enum.sum()

    max(ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT"), total_balance)
  end

  @doc """
  Return the combined effective balance of the active validators.
  Note: ``get_total_balance`` returns ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
  """
  @spec get_total_active_balance(BeaconState.t()) :: SszTypes.gwei()
  def get_total_active_balance(state) do
    current_epoch = get_current_epoch(state)
    validator_indices = get_active_validator_indices(state, current_epoch)
    get_total_balance(state, validator_indices)
  end
end
