defmodule LambdaEthereumConsensus.StateTransition.Accessors do
  @moduledoc """
  Functions accessing the current `BeaconState`
  """

  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.StateTransition.{Cache, Math, Misc, Predicates}
  alias LambdaEthereumConsensus.Utils
  alias LambdaEthereumConsensus.Utils.Randao
  alias Types.{Attestation, BeaconState, IndexedAttestation, SyncCommittee, Validator}

  @max_random_byte 2 ** 8 - 1

  @doc """
    Return the next sync committee, with possible pubkey duplicates.
  """
  @spec get_next_sync_committee(BeaconState.t()) ::
          {:ok, SyncCommittee.t()} | {:error, String.t()}
  def get_next_sync_committee(%BeaconState{validators: validators} = state) do
    with {:ok, indices} <- get_next_sync_committee_indices(state),
         pubkeys <- indices |> Enum.map(fn index -> Aja.Vector.at!(validators, index).pubkey end),
         {:ok, aggregate_pubkey} <- Bls.eth_aggregate_pubkeys(pubkeys) do
      {:ok, %SyncCommittee{pubkeys: pubkeys, aggregate_pubkey: aggregate_pubkey}}
    end
  end

  @spec get_next_sync_committee_indices(BeaconState.t()) ::
          {:ok, list(Types.validator_index())} | {:error, String.t()}
  defp get_next_sync_committee_indices(%BeaconState{validators: validators} = state) do
    # Return the sync committee indices, with possible duplicates, for the next sync committee.
    epoch = get_current_epoch(state) + 1
    active_validator_indices = get_active_validator_indices(state, epoch)
    active_validator_count = Aja.Vector.size(active_validator_indices)
    seed = get_seed(state, epoch, Constants.domain_sync_committee())

    compute_sync_committee_indices(
      active_validator_count,
      active_validator_indices,
      seed,
      validators
    )
  end

  defp compute_sync_committee_indices(
         active_validator_count,
         active_validator_indices,
         seed,
         validators
       ) do
    max_uint64 = 2 ** 64 - 1

    0..max_uint64
    |> Enum.reduce_while([], fn i, sync_committee_indices ->
      case compute_sync_committee_index_and_return_indices(
             i,
             active_validator_count,
             active_validator_indices,
             seed,
             validators,
             sync_committee_indices
           ) do
        {:ok, sync_committee_indices} ->
          sync_committee_indices_or_halt(sync_committee_indices)

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp sync_committee_indices_or_halt(sync_committee_indices) do
    case length(sync_committee_indices) < ChainSpec.get("SYNC_COMMITTEE_SIZE") do
      true -> {:cont, sync_committee_indices}
      false -> {:halt, {:ok, Enum.reverse(sync_committee_indices)}}
    end
  end

  defp compute_sync_committee_index_and_return_indices(
         index,
         active_validator_count,
         active_validator_indices,
         seed,
         validators,
         sync_committee_indices
       ) do
    with {:ok, shuffled_index} <-
           rem(index, active_validator_count)
           |> Misc.compute_shuffled_index(active_validator_count, seed) do
      candidate_index = Aja.Vector.at!(active_validator_indices, shuffled_index)

      <<_::binary-size(rem(index, 32)), random_byte, _::binary>> =
        SszEx.hash(seed <> Misc.uint64_to_bytes(div(index, 32)))

      max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")
      effective_balance = Aja.Vector.at!(validators, candidate_index).effective_balance

      if effective_balance * @max_random_byte >= max_effective_balance * random_byte do
        {:ok, sync_committee_indices |> List.insert_at(0, candidate_index)}
      else
        {:ok, sync_committee_indices}
      end
    end
  end

  @doc """
  Return the sequence of active validator indices at ``epoch``.
  """
  @spec get_active_validator_indices(BeaconState.t(), Types.epoch()) ::
          Aja.Vector.t(Types.validator_index())
  def get_active_validator_indices(%BeaconState{validators: validators} = state, epoch) do
    compute_fn = fn ->
      validators
      |> Aja.Vector.with_index()
      |> Aja.Vector.filter(fn {v, _} -> Predicates.is_active_validator(v, epoch) end)
      |> Aja.Vector.map(fn {_, index} -> index end)
    end

    case get_epoch_root(state, epoch) do
      {:ok, root} -> Cache.lazily_compute(:active_validator_indices, {epoch, root}, compute_fn)
      _ -> compute_fn.()
    end
  end

  @doc """
  Return the current epoch.
  """
  @spec get_current_epoch(BeaconState.t()) :: Types.epoch()
  def get_current_epoch(%BeaconState{slot: slot}) do
    Misc.compute_epoch_at_slot(slot)
  end

  @doc """
  Return the previous epoch (unless the current epoch is ``GENESIS_EPOCH``).
  """
  @spec get_previous_epoch(BeaconState.t()) :: Types.epoch()
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
  @spec get_unslashed_participating_indices(BeaconState.t(), integer, Types.epoch()) ::
          {:ok, MapSet.t()} | {:error, String.t()}
  def get_unslashed_participating_indices(%BeaconState{} = state, flag_index, epoch) do
    if epoch in [get_previous_epoch(state), get_current_epoch(state)] do
      epoch_participation =
        if epoch == get_current_epoch(state) do
          state.current_epoch_participation
        else
          state.previous_epoch_participation
        end

      participating_indices =
        state.validators
        |> Aja.Vector.zip_with(epoch_participation, fn v, participation ->
          not v.slashed and Predicates.is_active_validator(v, epoch) and
            Predicates.has_flag(participation, flag_index)
        end)
        |> Aja.Vector.with_index()
        |> Aja.Vector.filter(&elem(&1, 0))
        |> Aja.Vector.map(fn {true, index} -> index end)
        |> MapSet.new()

      {:ok, participating_indices}
    else
      {:error, "epoch is not current or previous epochs"}
    end
  end

  @doc """
  Return the combined effective balance of the active validators.
  Note: ``get_total_balance`` returns ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
  """
  @spec get_total_active_balance(BeaconState.t()) :: Types.gwei()
  def get_total_active_balance(state) do
    epoch = get_current_epoch(state)
    {:ok, root} = get_epoch_root(state, epoch)

    Cache.lazily_compute(:total_active_balance, {epoch, root}, fn ->
      state.validators
      |> Stream.filter(&Predicates.is_active_validator(&1, epoch))
      |> Stream.map(fn %Validator{effective_balance: effective_balance} -> effective_balance end)
      |> Enum.sum()
      |> max(ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT"))
    end)
  end

  @doc """
  Return the validator churn limit for the current epoch.
  """
  @spec get_validator_churn_limit(BeaconState.t()) :: Types.uint64()
  def get_validator_churn_limit(%BeaconState{} = state) do
    min_per_epoch_churn_limit = ChainSpec.get("MIN_PER_EPOCH_CHURN_LIMIT")
    churn_limit_quotient = ChainSpec.get("CHURN_LIMIT_QUOTIENT")

    get_active_validator_count(state, get_current_epoch(state))
    |> div(churn_limit_quotient)
    |> max(min_per_epoch_churn_limit)
  end

  @doc """
  Returns the number of epochs since the last finalised checkpoint (minus one).
  """
  @spec get_finality_delay(BeaconState.t()) :: Types.uint64()
  def get_finality_delay(%BeaconState{} = state) do
    get_previous_epoch(state) - state.finalized_checkpoint.epoch
  end

  @doc """
  These are the validators that were subject to rewards and penalties in the previous epoch.
  """
  @spec get_eligible_validator_indices(BeaconState.t()) :: list(Types.validator_index())
  def get_eligible_validator_indices(%BeaconState{validators: validators} = state) do
    previous_epoch = get_previous_epoch(state)

    validators
    |> Stream.with_index()
    |> Stream.filter(fn {validator, _index} ->
      Predicates.is_eligible_validator(validator, previous_epoch)
    end)
    |> Stream.map(fn {_validator, index} -> index end)
    |> Enum.to_list()
  end

  @doc """
  Return the beacon proposer index at the current slot.
  """
  @spec get_beacon_proposer_index(BeaconState.t()) ::
          {:ok, Types.validator_index()} | {:error, String.t()}
  def get_beacon_proposer_index(%BeaconState{slot: slot} = state) do
    epoch = get_current_epoch(state)
    {:ok, root} = get_epoch_root(state, epoch)

    Cache.lazily_compute(:beacon_proposer_index, {slot, root}, fn ->
      indices = get_active_validator_indices(state, epoch)

      state
      |> get_seed(epoch, Constants.domain_beacon_proposer())
      |> then(&SszEx.hash(&1 <> Misc.uint64_to_bytes(slot)))
      |> then(&Misc.compute_proposer_index(state, indices, &1))
    end)
  end

  defp get_state_epoch_root(state) do
    epoch = get_current_epoch(state)
    {:ok, root} = get_epoch_root(state, epoch)
    root
  end

  defp get_epoch_root(state, epoch) do
    epoch
    |> Misc.compute_start_slot_at_epoch()
    |> then(&get_block_root_at_slot(state, &1 - 1))
  end

  @doc """
  Return the number of committees in each slot for the given ``epoch``.
  """
  @spec get_committee_count_per_slot(BeaconState.t(), Types.epoch()) :: Types.uint64()
  def get_committee_count_per_slot(%BeaconState{} = state, epoch) do
    get_active_validator_count(state, epoch)
    |> div(ChainSpec.get("SLOTS_PER_EPOCH"))
    |> div(ChainSpec.get("TARGET_COMMITTEE_SIZE"))
    |> min(ChainSpec.get("MAX_COMMITTEES_PER_SLOT"))
    |> max(1)
  end

  @spec get_active_validator_count(BeaconState.t(), Types.epoch()) :: Types.uint64()
  def get_active_validator_count(%BeaconState{} = state, epoch) do
    Cache.lazily_compute(:active_validator_count, {epoch, get_state_epoch_root(state)}, fn ->
      Aja.Enum.count(state.validators, &Predicates.is_active_validator(&1, epoch))
    end)
  end

  @doc """
  Return the beacon committee at ``slot`` for ``index``.
  """
  @spec get_beacon_committee(BeaconState.t(), Types.slot(), Types.commitee_index()) ::
          {:ok, [Types.validator_index()]} | {:error, String.t()}
  def get_beacon_committee(%BeaconState{} = state, slot, index) do
    epoch = Misc.compute_epoch_at_slot(slot)

    compute_fn = fn ->
      committees_per_slot = get_committee_count_per_slot(state, epoch)
      indices = get_active_validator_indices(state, epoch)

      seed = get_seed(state, epoch, Constants.domain_beacon_attester())

      committee_index =
        rem(slot, ChainSpec.get("SLOTS_PER_EPOCH")) * committees_per_slot + index

      committee_count = committees_per_slot * ChainSpec.get("SLOTS_PER_EPOCH")

      Misc.compute_committee(indices, seed, committee_index, committee_count)
    end

    case get_epoch_root(state, epoch) do
      {:ok, root} -> Cache.lazily_compute(:beacon_committee, {slot, {index, root}}, compute_fn)
      _ -> compute_fn.()
    end
  end

  @spec get_base_reward_per_increment(BeaconState.t()) :: Types.gwei()
  def get_base_reward_per_increment(state) do
    numerator = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT") * ChainSpec.get("BASE_REWARD_FACTOR")
    denominator = state |> get_total_active_balance() |> Math.integer_squareroot()
    div(numerator, denominator)
  end

  @doc """
  Return the base reward for the validator defined by ``index`` with respect to the current ``state``.
  """
  @spec get_base_reward(BeaconState.t(), Types.validator_index()) :: Types.gwei()
  def get_base_reward(%BeaconState{} = state, index) do
    validator = Aja.Vector.at!(state.validators, index)
    get_base_reward(validator, get_base_reward_per_increment(state))
  end

  @spec get_base_reward(Types.Validator.t(), Types.gwei()) :: Types.gwei()
  def get_base_reward(%Types.Validator{} = validator, base_reward_per_increment) do
    effective_balance = validator.effective_balance

    increments = div(effective_balance, ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT"))

    increments * base_reward_per_increment
  end

  @doc """
  Return the flag indices that are satisfied by an attestation.
  """
  @spec get_attestation_participation_flag_indices(
          BeaconState.t(),
          Types.AttestationData.t(),
          Types.uint64()
        ) ::
          {:ok, list(Types.uint64())} | {:error, String.t()}
  def get_attestation_participation_flag_indices(state, data, inclusion_delay) do
    with :ok <- check_valid_source(state, data),
         {:ok, target_root} <-
           get_block_root(state, data.target.epoch) |> Utils.map_err("invalid target"),
         {:ok, head_root} <-
           get_block_root_at_slot(state, data.slot) |> Utils.map_err("invalid head") do
      is_matching_target = data.target.root == target_root
      is_matching_head = is_matching_target and data.beacon_block_root == head_root

      source_indices = compute_source_indices(inclusion_delay)
      target_indices = compute_target_indices(is_matching_target, inclusion_delay)
      head_indices = compute_head_indices(is_matching_head, inclusion_delay)

      {:ok, Enum.concat([source_indices, target_indices, head_indices])}
    end
  end

  defp check_valid_source(state, data) do
    justified_checkpoint =
      if data.target.epoch == get_current_epoch(state) do
        state.current_justified_checkpoint
      else
        state.previous_justified_checkpoint
      end

    if data.source == justified_checkpoint do
      :ok
    else
      {:error, "invalid source"}
    end
  end

  defp compute_source_indices(inclusion_delay) do
    max_delay = ChainSpec.get("SLOTS_PER_EPOCH") |> Math.integer_squareroot()
    if inclusion_delay <= max_delay, do: [Constants.timely_source_flag_index()], else: []
  end

  defp compute_target_indices(is_matching_target, inclusion_delay) do
    max_delay = ChainSpec.get("SLOTS_PER_EPOCH")

    if is_matching_target and inclusion_delay <= max_delay,
      do: [Constants.timely_target_flag_index()],
      else: []
  end

  defp compute_head_indices(is_matching_head, inclusion_delay) do
    min_inclusion_delay = ChainSpec.get("MIN_ATTESTATION_INCLUSION_DELAY")

    if is_matching_head and inclusion_delay == min_inclusion_delay,
      do: [Constants.timely_head_flag_index()],
      else: []
  end

  @doc """
  Return the block root at a recent ``slot``.
  """
  @spec get_block_root_at_slot(BeaconState.t(), Types.slot()) ::
          {:ok, Types.root()} | {:error, String.t()}
  def get_block_root_at_slot(state, slot) do
    slots_per_historical_root = ChainSpec.get("SLOTS_PER_HISTORICAL_ROOT")

    if slot < state.slot and state.slot <= slot + slots_per_historical_root do
      root = Enum.at(state.block_roots, rem(slot, slots_per_historical_root))
      {:ok, root}
    else
      {:error, "Block root not available"}
    end
  end

  @doc """
  Return the block root at the start of a recent ``epoch``.
  """
  @spec get_block_root(BeaconState.t(), Types.epoch()) ::
          {:ok, Types.root()} | {:error, String.t()}
  def get_block_root(state, epoch) do
    get_block_root_at_slot(state, Misc.compute_start_slot_at_epoch(epoch))
  end

  @doc """
  Return the seed at ``epoch``.
  """
  @spec get_seed(BeaconState.t(), Types.epoch(), Types.domain_type()) :: Types.bytes32()
  def get_seed(state, epoch, domain_type) do
    future_epoch =
      epoch + ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR") -
        ChainSpec.get("MIN_SEED_LOOKAHEAD") - 1

    mix = Randao.get_randao_mix(state, future_epoch)

    SszEx.hash(domain_type <> Misc.uint64_to_bytes(epoch) <> mix)
  end

  @doc """
  Return the signature domain (fork version concatenated with domain type) of a message.
  """
  @spec get_domain(BeaconState.t(), Types.domain_type(), Types.epoch() | nil) ::
          Types.domain()
  def get_domain(state, domain_type, epoch \\ nil) do
    epoch = if epoch == nil, do: get_current_epoch(state), else: epoch

    fork_version =
      if epoch < state.fork.epoch do
        state.fork.previous_version
      else
        state.fork.current_version
      end

    Misc.compute_domain(domain_type,
      fork_version: fork_version,
      genesis_validators_root: state.genesis_validators_root
    )
  end

  @doc """
  Return the indexed attestation corresponding to ``attestation``.
  """
  @spec get_indexed_attestation(BeaconState.t(), Attestation.t()) ::
          {:ok, IndexedAttestation.t()} | {:error, String.t()}
  def get_indexed_attestation(%BeaconState{} = state, attestation) do
    with {:ok, indices} <-
           get_attesting_indices(state, attestation.data, attestation.aggregation_bits) do
      %IndexedAttestation{
        attesting_indices: Enum.sort(indices),
        data: attestation.data,
        signature: attestation.signature
      }
      |> then(&{:ok, &1})
    end
  end

  @spec get_committee_indexed_attestation([Types.validator_index()], Attestation.t()) ::
          IndexedAttestation.t()
  def get_committee_indexed_attestation(beacon_committee, attestation) do
    indices = get_committee_attesting_indices(beacon_committee, attestation.aggregation_bits)

    %IndexedAttestation{
      attesting_indices: indices,
      data: attestation.data,
      signature: attestation.signature
    }
  end

  @doc """
  Return the set of attesting indices corresponding to ``data`` and ``bits``.
  """
  @spec get_attesting_indices(BeaconState.t(), Types.AttestationData.t(), Types.bitlist()) ::
          {:ok, MapSet.t()} | {:error, String.t()}
  def get_attesting_indices(%BeaconState{} = state, data, bits) do
    with {:ok, committee} <- get_beacon_committee(state, data.slot, data.index) do
      committee
      |> Stream.with_index()
      |> Stream.filter(fn {_value, index} -> participated?(bits, index) end)
      |> Stream.map(fn {value, _index} -> value end)
      |> MapSet.new()
      |> then(&{:ok, &1})
    end
  end

  @spec get_committee_attesting_indices([Types.validator_index()], Types.bitlist()) ::
          [Types.validator_index()]
  def get_committee_attesting_indices(committee, bits) do
    committee
    |> Stream.with_index()
    |> Stream.filter(fn {_value, index} -> participated?(bits, index) end)
    |> Stream.map(fn {value, _index} -> value end)
    |> Enum.sort()
  end

  defp participated?(bits, index) do
    # The bit order inside the byte is reversed (e.g. bits[0] is the 8th bit).
    # Here we keep the byte index the same, but reverse the bit index.
    bit_index = index + 7 - 2 * rem(index, 8)
    <<_::size(bit_index), flag::1, _::bits>> = bits
    flag == 1
  end

  @doc """
  Return the combined effective balance of the ``indices``.
  ``EFFECTIVE_BALANCE_INCREMENT`` Gwei minimum to avoid divisions by zero.
  Math safe up to ~10B ETH, after which this overflows uint64.
  """
  @spec get_total_balance(BeaconState.t(), Enumerable.t(Types.validator_index())) ::
          Types.gwei()
  def get_total_balance(state, indices) do
    indices = MapSet.new(indices)

    total_balance =
      state.validators
      |> Stream.with_index()
      |> Stream.filter(fn {_, index} -> MapSet.member?(indices, index) end)
      |> Stream.map(fn {%Types.Validator{effective_balance: n}, _} -> n end)
      |> Enum.sum()

    max(ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT"), total_balance)
  end
end
