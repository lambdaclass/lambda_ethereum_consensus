defmodule LambdaEthereumConsensus.StateTransition.Misc do
  @moduledoc """
  Misc functions
  """

  import Bitwise
  require Aja
  require Logger

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Shuffling
  alias LambdaEthereumConsensus.Utils
  alias Types.BeaconState

  @max_random_byte 2 ** 16 - 1

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
  @spec compute_proposer_index(BeaconState.t(), Aja.Vector.t(), Types.bytes32()) ::
          {:error, String.t()}
  def compute_proposer_index(_state, Aja.vec([]), _seed), do: {:error, "Empty indices"}

  @spec compute_proposer_index(
          BeaconState.t(),
          Aja.Vector.t(Types.validator_index()),
          Types.bytes32()
        ) ::
          {:ok, Types.validator_index()}
  def compute_proposer_index(state, indices, seed) do
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE_ELECTRA")
    total = Aja.Vector.size(indices)

    Stream.iterate(0, &(&1 + 1))
    |> Stream.map(fn i ->
      {:ok, index} = compute_shuffled_index(rem(i, total), total, seed)
      candidate_index = Aja.Vector.at!(indices, index)

      random_bytes = SszEx.hash(seed <> uint_to_bytes(div(i, 16), 64))
      offset = rem(i, 16) * 2

      bytes = binary_part(random_bytes, offset, 2) <> <<0::48>>
      random_value = bytes_to_uint64(bytes)

      effective_balance = Aja.Vector.at(state.validators, candidate_index).effective_balance

      {effective_balance, random_value, candidate_index}
    end)
    |> Stream.filter(fn {effective_balance, random_value, _} ->
      effective_balance * @max_random_byte >= max_effective_balance * random_value
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

  @spec uint_to_bytes(non_neg_integer(), 8 | 16 | 32 | 64) :: binary()
  def uint_to_bytes(value, size) do
    # Converts an unsigned integer value to a bytes value
    <<value::unsigned-integer-little-size(size)>>
  end

  @spec uint64_to_bytes(Types.uint64()) :: <<_::64>>
  def uint64_to_bytes(value) when is_integer(value) and value >= 0 do
    <<value::unsigned-integer-little-size(64)>>
  end

  @doc """
  Gets all committees for a single epoch. More efficient than calculating each one, as the shuffling
  is done a single time for the whole index list and shared values are reused between committees.
  """
  @spec compute_all_committees(BeaconState.t(), Types.epoch()) :: list(Aja.Vector.t())
  def compute_all_committees(state, epoch) do
    indices = Accessors.get_active_validator_indices(state, epoch)
    index_count = Aja.Vector.size(indices)
    seed = Accessors.get_seed(state, epoch, Constants.domain_beacon_attester())

    shuffled_indices = Shuffling.shuffle_list(indices, seed) |> Aja.Vector.to_list()

    committee_count =
      Accessors.get_committee_count_per_slot(state, epoch) * ChainSpec.get("SLOTS_PER_EPOCH")

    committee_sizes =
      Enum.map(0..(committee_count - 1), fn index ->
        {c_start, c_end} = committee_boundaries(index, index_count, committee_count)
        c_end - c_start + 1
      end)

    # separate using sizes.
    Utils.chunk_by_sizes(shuffled_indices, committee_sizes)
  end

  @doc """
  Computes the validator indices of the ``committee_index``-th committee at some epoch
  with ``committee_count`` committees, and for some given ``indices`` and ``seed``.

  Args:
  - indices: a full list of all active validator indices for a single epoch.
  - seed: for shuffling calculations.
  - committee_index: global number representing the order of the requested committee within the
    whole epoch.
  - committee_count: total amount of committees for the epoch. Useful to determine the start and end
    of the requested committee.

  Returns:
  - The list of indices for the validators that conform the requested committee. The order is the
    same as used in the aggregation bits of an attestation in that committee.

  PERFORMANCE NOTE:

  Instead of shuffling the full index list, it focuses on the positions of the requested committee
  and calculates their shuffled index. Because of the symmetric nature of the shuffling algorithm,
  looking at the shuffled index position in the index list gives the element that would end up in
  the committee if the full list was to be shuffled.

  This is, in logic, equivalent to shuffling the whole validator index list and getting the
  elements for the committee under calculation, but only calculating the shuffling for the elements
  of the committee.

  While the amount of calculations is smaller than the full shuffling, calling this for every
  committee in an epoch is inefficient. For that end, compute_all_committees should be called.
  """
  @spec compute_committee(Aja.Vector.t(), Types.bytes32(), Types.uint64(), Types.uint64()) ::
          {:error, String.t()}
  def compute_committee(Aja.vec([]), _, _, _), do: {:error, "Empty indices"}

  @spec compute_committee(
          Aja.Vector.t(Types.validator_index()),
          Types.bytes32(),
          Types.uint64(),
          Types.uint64()
        ) :: {:ok, [Types.validator_index()]}
  def compute_committee(indices, seed, committee_index, committee_count)
      when committee_index < committee_count do
    index_count = Aja.Vector.size(indices)

    {committee_start, committee_end} =
      committee_boundaries(committee_index, index_count, committee_count)

    committee_start..committee_end//1
    # NOTE: this cannot fail because committee_end < index_count
    |> Enum.map(fn i ->
      {:ok, index} = compute_shuffled_index(i, index_count, seed)
      Aja.Vector.at!(indices, index)
    end)
    |> then(&{:ok, &1})
  end

  def compute_committee(_, _, _, _), do: {:error, "Invalid committee index"}

  @doc """
  Computes the boundaries of a committee.

  Args:
  - committee_index: epoch based committee index.
  - index_count: amount of active validators participating in the epoch.
  - committee_count: amount of committees that will be formed in the epoch.
  """
  def committee_boundaries(committee_index, index_count, committee_count) do
    committee_start = div(index_count * committee_index, committee_count)
    committee_end = div(index_count * (committee_index + 1), committee_count) - 1
    {committee_start, committee_end}
  end

  @doc """
  Compute the sync committee period for the given ``epoch``. This is used to determine the
  period in which a validator is assigned to the sync committee.
  """
  @spec compute_sync_committee_period(Types.epoch()) :: Types.uint64()
  def compute_sync_committee_period(epoch) do
    div(epoch, ChainSpec.get("EPOCHS_PER_SYNC_COMMITTEE_PERIOD"))
  end

  @spec sync_subcommittee_size() :: Types.uint64()
  def sync_subcommittee_size() do
    div(ChainSpec.get("SYNC_COMMITTEE_SIZE"), Constants.sync_committee_subnet_count())
  end

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

  @spec compute_signing_root(any(), SszEx.schema(), Types.domain()) :: Types.root()
  def compute_signing_root(ssz_object, schema, domain) do
    ssz_object |> SszEx.hash_tree_root!(schema) |> compute_signing_root(domain)
  end

  @doc """
  Return a new ``ParticipationFlags`` adding ``flag_index`` to ``flags``.
  """
  @spec add_flag(Types.participation_flags(), integer) :: Types.participation_flags()
  def add_flag(flags, flag_index) do
    flag = :math.pow(2, flag_index) |> round()
    bor(flags, flag)
  end

  @spec get_latest_block_hash(BeaconState.t()) :: Types.root()
  def get_latest_block_hash(anchor_state) do
    state_root = Ssz.hash_tree_root!(anchor_state)
    # The latest_block_header.state_root was zeroed out to avoid circular dependencies
    anchor_state.latest_block_header
    |> Map.put(:state_root, state_root)
    |> Ssz.hash_tree_root!()
  end

  @spec kzg_commitment_to_versioned_hash(Types.kzg_commitment()) :: Types.bytes32()
  def kzg_commitment_to_versioned_hash(kzg_commitment) do
    hash = SszEx.hash(kzg_commitment) |> binary_slice(1..31)
    <<Constants.versioned_hash_version_kzg()::binary-size(1), hash::binary-size(31)>>
  end
end
