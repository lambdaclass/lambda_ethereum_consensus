defmodule LambdaEthereumConsensus.StateTransition.Misc do
  @moduledoc """
  Misc functions
  """

  alias LambdaEthereumConsensus.StateTransition.Math
  alias LambdaEthereumConsensus.Beacon.HelperFunctions
  import Bitwise

  @doc """
  Returns the epoch number at slot.
  """
  @spec compute_epoch_at_slot(SszTypes.slot()) :: SszTypes.epoch()
  def compute_epoch_at_slot(slot) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    div(slot, slots_per_epoch)
  end

  @doc """
  Return the epoch during which validator activations and exits initiated in ``epoch`` take effect.
  """
  @spec compute_activation_exit_epoch(SszTypes.epoch()) :: SszTypes.epoch()
  def compute_activation_exit_epoch(epoch) do
    max_seed_lookahead = ChainSpec.get("MAX_SEED_LOOKAHEAD")
    epoch + 1 + max_seed_lookahead
  end

  @doc """
  Return the shuffled index corresponding to ``seed`` (and ``index_count``).
  """
  @spec compute_shuffled_index(SszTypes.uint64(), SszTypes.uint64(), SszTypes.bytes32()) ::
          {:error, String.t()}
  def compute_shuffled_index(index, index_count, _seed)
      when index >= index_count or index_count == 0 do
    {:error, "invalid index_count"}
  end

  @spec compute_shuffled_index(SszTypes.uint64(), SszTypes.uint64(), SszTypes.bytes32()) ::
          {:ok, SszTypes.uint64()}
  def compute_shuffled_index(index, index_count, seed) do
    shuffle_round_count = ChainSpec.get("SHUFFLE_ROUND_COUNT")

    new_index =
      Enum.reduce(0..(shuffle_round_count - 1), index, fn round, current_index ->
        round_as_bytes = <<round>>

        hash_of_seed_round = :crypto.hash(:sha256, seed <> round_as_bytes)

        pivot = rem(bytes_to_uint64(hash_of_seed_round), index_count)

        flip = rem(pivot + index_count - current_index, index_count)
        position = max(current_index, flip)

        position_div_256 = uint_to_bytes4(div(position, 256))

        source =
          :crypto.hash(:sha256, seed <> round_as_bytes <> position_div_256)

        byte_index = div(rem(position, 256), 8)
        <<_::binary-size(byte_index), byte, _::binary>> = source
        right_shift = byte >>> rem(position, 8)
        bit = rem(right_shift, 2)

        current_index =
          if bit == 1 do
            flip
          else
            current_index
          end

        current_index
      end)

    {:ok, new_index}
  end

  @spec increase_inactivity_score(SszTypes.uint64(), integer, MapSet.t(), SszTypes.uint64()) ::
          SszTypes.uint64()
  def increase_inactivity_score(
        inactivity_score,
        index,
        unslashed_participating_indices,
        inactivity_score_bias
      ) do
    if MapSet.member?(unslashed_participating_indices, index) do
      inactivity_score - min(1, inactivity_score)
    else
      inactivity_score + inactivity_score_bias
    end
  end

  @spec decrease_inactivity_score(SszTypes.uint64(), boolean, SszTypes.uint64()) ::
          SszTypes.uint64()
  def decrease_inactivity_score(
        inactivity_score,
        state_is_in_inactivity_leak,
        inactivity_score_recovery_rate
      ) do
    if state_is_in_inactivity_leak do
      inactivity_score
    else
      inactivity_score - min(inactivity_score_recovery_rate, inactivity_score)
    end
  end

  @spec update_inactivity_score(%{integer => SszTypes.uint64()}, integer, {SszTypes.uint64()}) ::
          SszTypes.uint64()
  def update_inactivity_score(updated_eligible_validator_indices, index, inactivity_score) do
    case Map.fetch(updated_eligible_validator_indices, index) do
      {:ok, new_eligible_validator_index} -> new_eligible_validator_index
      :error -> inactivity_score
    end
  end

  @doc """
  Return the start slot of ``epoch``.
  """
  @spec compute_start_slot_at_epoch(SszTypes.epoch()) :: SszTypes.slot()
  def compute_start_slot_at_epoch(epoch) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    epoch * slots_per_epoch
  end

  @spec bytes_to_uint64(binary()) :: SszTypes.uint64()
  defp bytes_to_uint64(value) do
    # Converts a binary value to a 64-bit unsigned integer
    <<first_8_bytes::unsigned-integer-little-size(64), _::binary>> = value
    first_8_bytes
  end

  @spec uint_to_bytes4(integer()) :: SszTypes.bytes4()
  defp uint_to_bytes4(value) do
    # Converts an unsigned integer value to a bytes 4 value
    <<value::unsigned-integer-little-size(32)>>
  end

  @doc """
  Return the committee corresponding to ``indices``, ``seed``, ``index``, and committee ``count``.
  """
  @spec compute_committee(
          list(SszTypes.validator_index()),
          SszTypes.bytes32(),
          SszTypes.uint64(),
          SszTypes.uint64()
        ) ::
          list(SszTypes.validator_index())
  def compute_committee(indices, seed, index, count) do
    start_ = div(length(indices) * index, count)
    # Subtract 1 to ensure exclusion of the last index
    end_ = div(length(indices) * (index + 1), count) - 1

    Enum.map(start_..end_, fn i ->
      {:ok, shuffled_index} = compute_shuffled_index(i, length(indices), seed)
      Enum.at(indices, shuffled_index)
    end)
  end

  @doc """
  Return the domain for the ``domain_type`` and ``fork_version``.
  """
  @spec compute_domain(SszTypes.domain_type(), SszTypes.version(), SszTypes.root()) ::
          SszTypes.domain()
  def compute_domain(domain_type, fork_version, genesis_validators_root) do
    computed_fork_version =
      if fork_version == nil do
        ChainSpec.get("GENESIS_FORK_VERSION")
      else
        fork_version
      end

    computed_genesis_validators_root =
      if genesis_validators_root == nil do
        # all bytes zero by default
        <<0>>
      else
        genesis_validators_root
      end

    fork_data_root =
      HelperFunctions.compute_fork_data_root(
        computed_fork_version,
        computed_genesis_validators_root
      )

    <<fork_data_prefix::binary-size(28), _rest::binary>> = fork_data_root
    domain_type <> fork_data_prefix
  end

  @doc """
  Return the signing root for the corresponding signing data.
  """
  @spec compute_signing_root(any(), SszTypes.domain()) :: SszTypes.root()
  def compute_signing_root(ssz_object, domain) do
    Ssz.hash_tree_root({Ssz.hash_tree_root(ssz_object), domain})
  end

  @doc """
  Return from ``indices`` a random index sampled by effective balance.
  """
  @spec compute_proposer_index(
          BeaconState.t(),
          list(SszTypes.validator_index()),
          SszTypes.bytes32()
        ) ::
          SszTypes.validator_index()
  def compute_proposer_index(state, indices, seed) when length(indices) > 0 do
    total = length(indices)
    compute_proposer_index(state, indices, seed, 0, total)
  end

  defp compute_proposer_index(_state, _indices, _seed, i, total) when i >= total, do: nil

  defp compute_proposer_index(state, indices, seed, i, total) do
    max_random_byte = 255
    {:ok, shuffled_index} = compute_shuffled_index(rem(i, total), total, seed)
    candidate_index = Enum.at(indices, shuffled_index)

    random_byte =
      :crypto.hash(:sha256, seed <> Math.uint_to_bytes(div(i, 32)))
      |> :binary.part(rem(i, 32), 1)
      |> :binary.decode_unsigned()

    validator = Enum.at(state.validators, candidate_index)
    effective_balance = validator.effective_balance

    if effective_balance * max_random_byte >= ChainSpec.get("MAX_EFFECTIVE_BALANCE") * random_byte do
      candidate_index
    else
      compute_proposer_index(state, indices, seed, i + 1, total)
    end
  end

  @doc """
  Return a new ``ParticipationFlags`` adding ``flag_index`` to ``flags``.
  """
  @spec add_flag(SszTypes.participation_flags(), integer) :: SszTypes.participation_flags()
  def add_flag(flags, flag_index) do
    flag = :math.pow(2, flag_index) |> round
    bor(flags, flag)
  end
end
