defmodule LambdaEthereumConsensus.StateTransition.Misc do
  @moduledoc """
  Misc functions
  """

  import Bitwise

  alias LambdaEthereumConsensus.SszEx
  alias Types.BeaconState

  @max_random_byte 2 ** 8 - 1

  @doc """
  Returns the Unix timestamp at the start of the given slot
  """
  @spec compute_timestamp_at_slot(BeaconState.t(), Types.uint64()) :: Types.uint64()
  def compute_timestamp_at_slot(state, slot) do
    slots_since_genesis = slot - Constants.genesis_slot()
    state.genesis_time + slots_since_genesis * ChainSpec.get("SECONDS_PER_SLOT")
  end

  @doc """
  Returns the epoch number at slot.
  """
  @spec compute_epoch_at_slot(Types.slot()) :: Types.epoch()
  def compute_epoch_at_slot(slot) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    div(slot, slots_per_epoch)
  end

  @doc """
  Return the epoch during which validator activations and exits initiated in ``epoch`` take effect.
  """
  @spec compute_activation_exit_epoch(Types.epoch()) :: Types.epoch()
  def compute_activation_exit_epoch(epoch) do
    max_seed_lookahead = ChainSpec.get("MAX_SEED_LOOKAHEAD")
    epoch + 1 + max_seed_lookahead
  end

  @doc """
  Return the shuffled index corresponding to ``seed`` (and ``index_count``).
  """
  @spec compute_shuffled_index(Types.uint64(), Types.uint64(), Types.bytes32()) ::
          {:error, String.t()}
  def compute_shuffled_index(index, index_count, _seed)
      when index >= index_count or index_count == 0 do
    {:error, "invalid index_count"}
  end

  @spec compute_shuffled_index(Types.uint64(), Types.uint64(), Types.bytes32()) ::
          {:ok, Types.uint64()}
  def compute_shuffled_index(index, index_count, seed) do
    shuffle_round_count = ChainSpec.get("SHUFFLE_ROUND_COUNT")

    0..(shuffle_round_count - 1)
    |> Enum.reduce(index, fn round, current_index ->
      pivot = SszEx.hash(seed <> <<round>>) |> bytes_to_uint64() |> rem(index_count)

      flip = rem(pivot + index_count - current_index, index_count)
      position = max(current_index, flip)

      position_div_256 = position |> div(256) |> uint_to_bytes(32)

      source = SszEx.hash(seed <> <<round>> <> position_div_256)

      bit_index = rem(position, 256) + 7 - 2 * rem(position, 8)
      <<_::size(bit_index), bit::1, _::bits>> = source

      if bit == 1, do: flip, else: current_index
    end)
    |> then(&{:ok, &1})
  end

  @spec increase_inactivity_score(Types.uint64(), integer, MapSet.t(), Types.uint64()) ::
          Types.uint64()
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

  @spec decrease_inactivity_score(Types.uint64(), boolean, Types.uint64()) ::
          Types.uint64()
  def decrease_inactivity_score(inactivity_score, true, _inactivity_score_recovery_rate),
    do: inactivity_score

  def decrease_inactivity_score(inactivity_score, false, inactivity_score_recovery_rate),
    do: inactivity_score - min(inactivity_score_recovery_rate, inactivity_score)

  @spec update_inactivity_score(%{integer => Types.uint64()}, integer, {Types.uint64()}) ::
          Types.uint64()
  def update_inactivity_score(updated_eligible_validator_indices, index, inactivity_score) do
    case Map.fetch(updated_eligible_validator_indices, index) do
      {:ok, new_eligible_validator_index} -> new_eligible_validator_index
      :error -> inactivity_score
    end
  end

  @doc """
  Return the start slot of ``epoch``.
  """
  @spec compute_start_slot_at_epoch(Types.epoch()) :: Types.slot()
  def compute_start_slot_at_epoch(epoch) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    epoch * slots_per_epoch
  end

  @doc """
  Return from ``indices`` a random index sampled by effective balance.
  """
  @spec compute_proposer_index(BeaconState.t(), [], Types.bytes32()) ::
          {:error, String.t()}
  def compute_proposer_index(_state, [], _seed), do: {:error, "Empty indices"}

  @spec compute_proposer_index(
          BeaconState.t(),
          nonempty_list(Types.validator_index()),
          Types.bytes32()
        ) ::
          {:ok, Types.validator_index()}
  def compute_proposer_index(state, indices, seed) do
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")
    total = length(indices)

    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn i ->
      {:ok, index} = compute_shuffled_index(rem(i, total), total, seed)
      candidate_index = Enum.at(indices, index)

      <<_::binary-size(rem(i, 32)), random_byte, _::binary>> =
        SszEx.hash(seed <> uint_to_bytes(div(i, 32), 64))

      effective_balance = Enum.at(state.validators, candidate_index).effective_balance

      {effective_balance, random_byte, candidate_index}
    end)
    |> Stream.filter(fn {effective_balance, random_byte, _} ->
      effective_balance * @max_random_byte >= max_effective_balance * random_byte
    end)
    |> Enum.take(1)
    |> then(fn [{_, _, candidate_index}] -> {:ok, candidate_index} end)
  end

  @doc """
  Return the domain for the ``domain_type`` and ``fork_version``.
  """
  @spec compute_domain(Types.domain_type(), Keyword.t()) ::
          Types.domain()
  def compute_domain(domain_type, opts \\ []) do
    fork_version = Keyword.get(opts, :fork_version, ChainSpec.get("GENESIS_FORK_VERSION"))
    genesis_validators_root = Keyword.get(opts, :genesis_validators_root, <<0::256>>)

    compute_fork_data_root(fork_version, genesis_validators_root)
    |> binary_part(0, 28)
    |> then(&(domain_type <> &1))
  end

  @spec bytes_to_uint64(binary()) :: Types.uint64()
  def bytes_to_uint64(value) do
    # Converts a binary value to a 64-bit unsigned integer
    <<first_8_bytes::unsigned-integer-little-size(64), _::binary>> = value
    first_8_bytes
  end

  @spec uint_to_bytes(non_neg_integer(), 8 | 32 | 64) :: binary()
  def uint_to_bytes(value, size) do
    # Converts an unsigned integer value to a bytes value
    <<value::unsigned-integer-little-size(size)>>
  end

  @spec uint64_to_bytes(Types.uint64()) :: <<_::64>>
  def uint64_to_bytes(value) when is_integer(value) and value >= 0 do
    <<value::unsigned-integer-little-size(64)>>
  end

  @doc """
  Computes the validator indices of the ``committee_index``-th committee at some epoch
  with ``committee_count`` committees, and for some given ``indices`` and ``seed``.
  """
  @spec compute_committee([], Types.bytes32(), Types.uint64(), Types.uint64()) ::
          {:error, String.t()}
  def compute_committee([], _, _, _), do: {:error, "Empty indices"}

  @spec compute_committee(
          [Types.validator_index(), ...],
          Types.bytes32(),
          Types.uint64(),
          Types.uint64()
        ) :: {:ok, [Types.validator_index()]}
  def compute_committee(indices, seed, committee_index, committee_count)
      when committee_index < committee_count do
    index_count = length(indices)
    committee_start = div(index_count * committee_index, committee_count)
    committee_end = div(index_count * (committee_index + 1), committee_count) - 1

    to_swap_indices =
      committee_start..committee_end//1
      # NOTE: this cannot fail because committee_end < index_count
      |> Stream.map(fn i ->
        {:ok, index} = compute_shuffled_index(i, index_count, seed)
        index
      end)
      |> Stream.with_index()
      |> Enum.sort(fn {a, _}, {b, _} -> a <= b end)

    {swapped_indices, []} =
      indices
      |> Stream.with_index()
      |> Enum.flat_map_reduce(to_swap_indices, fn
        {v, i}, [{i, j} | tail] -> {[{v, j}], tail}
        _, acc -> {[], acc}
      end)

    swapped_indices
    |> Enum.sort(fn {_, a}, {_, b} -> a <= b end)
    |> Enum.map(fn {v, _} -> v end)
    |> then(&{:ok, &1})
  end

  def compute_committee(_, _, _, _), do: {:error, "Invalid committee index"}

  @doc """
  Return the 32-byte fork data root for the ``current_version`` and ``genesis_validators_root``.
  This is used primarily in signature domains to avoid collisions across forks/chains.
  """
  @spec compute_fork_data_root(Types.version(), Types.root()) :: Types.root()
  def compute_fork_data_root(current_version, genesis_validators_root) do
    Ssz.hash_tree_root!(%Types.ForkData{
      current_version: current_version,
      genesis_validators_root: genesis_validators_root
    })
  end

  @doc """
  Return the 4-byte fork digest for the ``current_version`` and ``genesis_validators_root``.
  This is a digest primarily used for domain separation on the p2p layer.
  4-bytes suffices for practical separation of forks/chains.
  """
  @spec compute_fork_digest(Types.version(), Types.root()) :: Types.fork_digest()
  def compute_fork_digest(current_version, genesis_validators_root) do
    compute_fork_data_root(current_version, genesis_validators_root)
    |> binary_part(0, 4)
  end

  @doc """
  Return the signing root for the corresponding signing data.
  """
  @spec compute_signing_root(Types.bytes32(), Types.domain()) :: Types.root()
  def compute_signing_root(<<_::256>> = root, domain) do
    Ssz.hash_tree_root!(%Types.SigningData{object_root: root, domain: domain})
  end

  @spec compute_signing_root(any(), Types.domain()) :: Types.root()
  def compute_signing_root(ssz_object, domain) do
    ssz_object |> Ssz.hash_tree_root!() |> compute_signing_root(domain)
  end

  @spec compute_signing_root(any(), module(), Types.domain()) :: Types.root()
  def compute_signing_root(ssz_object, schema, domain) do
    ssz_object |> Ssz.hash_tree_root!(schema) |> compute_signing_root(domain)
  end

  @doc """
  Return a new ``ParticipationFlags`` adding ``flag_index`` to ``flags``.
  """
  @spec add_flag(Types.participation_flags(), integer) :: Types.participation_flags()
  def add_flag(flags, flag_index) do
    flag = :math.pow(2, flag_index) |> round
    bor(flags, flag)
  end

  @doc """
  Generates merkle proof from whole array
  """
  @spec get_merkle_proof(
          list(Types.bytes32()),
          integer
        ) :: Types.root()
  def get_merkle_proof(input_arr, n) do
    _get_merkle_proof(input_arr, n, [])
  end

  defp _get_merkle_proof([_ | []], _, acc), do: acc

  defp _get_merkle_proof(input_arr, n, acc) do
    e = if rem(n, 2) == 0, do: Enum.at(input_arr, n + 1), else: Enum.at(input_arr, n - 1)
    acc = acc ++ [e]
    _get_merkle_proof(one_level_up(input_arr), div(n, 2), acc)
  end


  @doc """
  Generates merkle proof by taking branch
  """
  @spec get_merkle_proof_by_branch(
      list(Types.bytes32())
    ) :: Types.root()
  def get_merkle_proof_by_branch(input_arr) do
    input_arr
    |> Enum.reduce(Enum.at(input_arr, 0), fn val1, val2 -> pair_hash(val1, val2) end)
  end


  @doc"""
  Generates merkle root
  """
  @spec get_merkle_root(list(Types.bytes32())) :: Types.root()
  def get_merkle_root(input_arr) do
    if(length(input_arr) > 1) do
      one_level_up(input_arr)
      |> get_merkle_root()
    else
      Enum.at(input_arr, 0)
    end
  end

  defp pair_hash(a, b) do
    IO.inspect(:crypto.hash(:sha256, :crypto.exor(:crypto.hash(:sha256, a), :crypto.hash(:sha256, b))))
    :crypto.hash(:sha256, :crypto.exor(:crypto.hash(:sha256, a), :crypto.hash(:sha256, b)))
  end

  defp one_level_up(input_arr) do
    if rem(length(input_arr), 2) == 1, do: input_arr ++ [<<0::256>>], else: input_arr
    |> Enum.chunk_every(2)
    |> _one_level_up([])
  end

  defp _one_level_up([], acc), do: acc

  defp _one_level_up([[a | [b | _]] | rem_arr], acc) do
    acc = acc ++ [pair_hash(a, b)]
    _one_level_up(rem_arr, acc)
  end
end
