defmodule LambdaEthereumConsensus.StateTransition.Misc do
  @moduledoc """
  Misc functions
  """

  alias LambdaEthereumConsensus.StateTransition.HelperFunctions

  @doc """
  Returns the epoch number at slot.
  """
  @spec compute_epoch_at_slot(SszTypes.slot()) :: SszTypes.epoch()
  def compute_epoch_at_slot(slot) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    div(slot, slots_per_epoch)
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
  Return the committee corresponding to ``indices``, ``seed``, ``index``, and committee ``count``.
  """
  @spec compute_committee(list(SszTypes.validator_index()), SszTypes.bytes32(), SszTypes.uint64(), SszTypes.uint64()) 
          :: list(SszTypes.validator_index())
  def compute_committee(indices, seed, index, count) do
    start_ = trunc((length(indices) * index) / count)
    end_ = trunc((length(indices) * (index + 1)) / count) - 1 # Subtract 1 since ranges are inclusive
    # TODO: make mapping nicer
    Enum.map(start_..end_, fn i ->
      {_, shuffled_index} = compute_shuffled_index(i, length(indices), seed)
      Enum.at(indices, shuffled_index)
    end)
  end

  @doc """
  Return the domain for the ``domain_type`` and ``fork_version``.
  """
  @spec compute_domain(SszTypes.domain_type(), SszTypes.version(), SszTypes.root()) :: SszTypes.domain()
  def compute_domain(domain_type, fork_version, genesis_validators_root) do
    computed_fork_version = 
      if fork_version == nil do
        ChainSpec.get("GENESIS_FORK_VERSION")
      else
        fork_version
      end
    computed_genesis_validators_root = 
      if genesis_validators_root == nil do
        <<0>>  # all bytes zero by default
      else
        genesis_validators_root
      end
    fork_data_root = HelperFunctions.compute_fork_data_root(computed_fork_version, computed_genesis_validators_root)
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
     Return the shuffled index corresponding to ``seed`` (and ``index_count``).
  """
  @spec compute_shuffled_index(SszTypes.uint64(), SszTypes.uint64(), SszTypes.bytes32()) ::
          {:ok, SszTypes.uint64()} | {:error, String.t()}
  def compute_shuffled_index(index, index_count, seed) do
    unless index < index_count do
      {:error, "index not less than index count"}
    end

    shuffle_round_count = ChainSpec.get("SHUFFLE_ROUND_COUNT")

    new_index =
      Enum.reduce(0..(shuffle_round_count - 1), index, fn round, current_index ->
        round_as_bytes =
          <<round::8>> |> :binary.decode_unsigned() |> :binary.encode_unsigned(:little)

        seed_as_bytes = seed |> :binary.decode_unsigned() |> :binary.encode_unsigned(:little)
        hash_of_seed_round = :crypto.hash(:sha256, seed_as_bytes <> round_as_bytes)

        first_8_bytes_of_hash_of_seed_round =
          hash_of_seed_round |> :binary.bin_to_list({0, 8}) |> :binary.list_to_bin()

        pivot = :binary.decode_unsigned(first_8_bytes_of_hash_of_seed_round, :little)

        flip = rem(pivot + index_count - current_index, index_count)
        position = max(current_index, flip)

        position_div_256 =
          <<div(position, 256)::32>>
          |> :binary.decode_unsigned()
          |> :binary.encode_unsigned(:little)

        source = :crypto.hash(:sha256, seed_as_bytes <> round_as_bytes <> position_div_256)
        byte_index = div(rem(position, 256), 8)
        byte = source |> :binary.bin_to_list() |> Enum.fetch!(byte_index)
        right_shift = :erlang.bsr(byte, rem(position, 8))
        bit = rem(right_shift, 2)

        index =
          if bit !== 0 do
            flip
          else
            current_index
          end

        {:ok, index}
      end)

    new_index
  end

  @doc """
  Return from ``indices`` a random index sampled by effective balance.
  """
  @spec compute_proposer_index(BeaconState.t(), list(SszTypes.validator_index()), SszTypes.bytes32()) ::
          SszTypes.validator_index()
  def compute_proposer_index(state, indices, seed) when length(indices) > 0 do
    total = length(indices)
    compute_proposer_index(state, indices, seed, 0, total)
  end
  
  defp compute_proposer_index(_state, _indices, _seed, i, total) when i >= total, do: nil
  
  defp compute_proposer_index(state, indices, seed, i, total) do
    max_random_byte = 255
    candidate_index = Enum.at(indices, compute_shuffled_index(rem(i, total), total, seed))
    
    random_byte = :crypto.hash(:sha256, seed <> Helper.uint_to_bytes(div(i, 32)))
      |> :binary.part(rem(i, 32), 1)
      |> :binary.decode_unsigned()
    
    effective_balance = state.validators[candidate_index].effective_balance
    
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
    Bitwise.bor(flags, flag)
  end
end
