defmodule LambdaEthereumConsensus.StateTransition.Misc do
  @moduledoc """
  Misc functions
  """

  alias SszTypes.BeaconState
  import Bitwise
  alias SszTypes.BeaconState

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

  @doc """
  Return from ``indices`` a random index sampled by effective balance.
  """
  @spec compute_proposer_index(BeaconState.t(), [SszTypes.validator_index()], SszTypes.bytes32()) ::
          {:ok, SszTypes.validator_index()} | {:error, binary()}
  def compute_proposer_index(state, indices, seed) do
    if length(indices) <= 0 do
      {:error, "Empty indices"}
    else
      {:ok, compute_proposer_index(state, indices, seed, 0)}
    end
  end

  defp compute_proposer_index(state, indices, seed, i) when i < length(indices) do
    max_random_byte = 2 ** 8 - 1
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

    total = length(indices)
    {:ok, i} = compute_shuffled_index(rem(i, total), total, seed)
    candidate_index = Enum.at(indices, i)
    random_byte = :crypto.hash(:sha256, seed <> uint_to_bytes4(div(i, 32)))
    <<_::binary-size(rem(i, 32)), byte, _::binary>> = random_byte

    effective_balance = Enum.at(state.validators, candidate_index).effective_balance

    if effective_balance * max_random_byte >= max_effective_balance * byte do
      candidate_index
    else
      compute_proposer_index(state, indices, seed, i + 1)
    end
  end

  @doc """
  Return the domain for the ``domain_type`` and ``fork_version``.
  """
  @spec compute_domain(SszTypes.domain_type(), Keyword.t()) ::
          SszTypes.domain()
  def compute_domain(domain_type, opts \\ []) do
    fork_version = Keyword.get(opts, :fork_version, ChainSpec.get("GENESIS_FORK_VERSION"))
    genesis_validators_root = Keyword.get(opts, :genesis_validators_root, <<0::256>>)

    compute_fork_data_root(fork_version, genesis_validators_root)
    |> binary_part(0, 28)
    |> then(&(domain_type <> &1))
  end

  @spec bytes_to_uint64(binary()) :: SszTypes.uint64()
  def bytes_to_uint64(value) do
    # Converts a binary value to a 64-bit unsigned integer
    <<first_8_bytes::unsigned-integer-little-size(64), _::binary>> = value
    first_8_bytes
  end

  @spec uint_to_bytes4(integer()) :: SszTypes.bytes4()
  def uint_to_bytes4(value) do
    # Converts an unsigned integer value to a bytes 4 value
    <<value::unsigned-integer-little-size(32)>>
  end

  @spec uint64_to_bytes(SszTypes.uint64()) :: <<_::64>>
  def uint64_to_bytes(value) when is_integer(value) and value >= 0 do
    <<value::unsigned-integer-little-size(64)>>
  end

  @spec compute_committee(
          list(SszTypes.validator_index()),
          SszTypes.bytes32(),
          SszTypes.uint64(),
          SszTypes.uint64()
        ) ::
          {:ok, list(SszTypes.validator_index())} | {:error, binary()}
  def compute_committee(indices, seed, index, count) do
    start_ = div(length(indices) * index, count)
    end_ = div(length(indices) * (index + 1), count) - 1

    case compute_committee_indices(start_, end_, indices, seed) do
      {:ok, result_list} -> {:ok, Enum.reverse(result_list)}
      _ -> {:error, "invalid index_count"}
    end
  end

  defp compute_committee_indices(start_, end_, indices, seed) do
    Enum.reduce_while(start_..end_, {:ok, []}, fn i, {:ok, acc_list} ->
      case compute_shuffled_index(i, length(indices), seed) do
        {:ok, shuffled_index} ->
          {:cont, {:ok, [Enum.at(indices, shuffled_index) | acc_list]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  @doc """
  Return the 32-byte fork data root for the ``current_version`` and ``genesis_validators_root``.
  This is used primarily in signature domains to avoid collisions across forks/chains.
  """
  @spec compute_fork_data_root(SszTypes.version(), SszTypes.root()) :: SszTypes.root()
  def compute_fork_data_root(current_version, genesis_validators_root) do
    Ssz.hash_tree_root!(%SszTypes.ForkData{
      current_version: current_version,
      genesis_validators_root: genesis_validators_root
    })
  end

  @doc """
  Return the 4-byte fork digest for the ``current_version`` and ``genesis_validators_root``.
  This is a digest primarily used for domain separation on the p2p layer.
  4-bytes suffices for practical separation of forks/chains.
  """
  @spec compute_fork_digest(SszTypes.version(), SszTypes.root()) :: SszTypes.fork_digest()
  def compute_fork_digest(current_version, genesis_validators_root) do
    compute_fork_data_root(current_version, genesis_validators_root)
    |> binary_part(0, 4)
  end

  @doc """
  Return the signing root for the corresponding signing data.
  """
  @spec compute_signing_root(SszTypes.bytes32(), SszTypes.domain()) :: SszTypes.root()
  def compute_signing_root(<<_::256>> = data, domain) do
    {:ok, root} =
      Ssz.hash_tree_root(%SszTypes.SigningData{
        object_root: data,
        domain: domain
      })

    root
  end

  @spec compute_signing_root(any(), SszTypes.domain()) :: SszTypes.root()
  def compute_signing_root(ssz_object, domain) do
    Ssz.hash_tree_root!(%SszTypes.SigningData{
      object_root: Ssz.hash_tree_root!(ssz_object),
      domain: domain
    })
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
