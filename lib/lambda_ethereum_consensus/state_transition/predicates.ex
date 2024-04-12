defmodule LambdaEthereumConsensus.StateTransition.Predicates do
  @moduledoc """
  Range of predicates enabling verification of state
  """

  alias LambdaEthereumConsensus.SszEx.Hash
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.BeaconState
  alias Types.Validator

  import Bitwise

  @doc """
  Check if ``validator`` is active.
  """
  @spec active_validator?(Validator.t(), Types.epoch()) :: boolean
  def active_validator?(
        %Validator{activation_epoch: activation_epoch, exit_epoch: exit_epoch},
        epoch
      ) do
    activation_epoch <= epoch && epoch < exit_epoch
  end

  @doc """
  Check if ``validator`` is eligible for rewards and penalties.
  """
  @spec eligible_validator?(Validator.t(), Types.epoch()) :: boolean
  def eligible_validator?(%Validator{} = validator, previous_epoch) do
    active_validator?(validator, previous_epoch) ||
      (validator.slashed && previous_epoch + 1 < validator.withdrawable_epoch)
  end

  @doc """
  If the beacon chain has not managed to finalise a checkpoint for MIN_EPOCHS_TO_INACTIVITY_PENALTY epochs
  Check if ``validator`` is eligible to be placed into the activation queue.
  """
  @spec eligible_for_activation_queue?(Validator.t()) :: boolean
  def eligible_for_activation_queue?(%Validator{} = validator) do
    far_future_epoch = Constants.far_future_epoch()
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

    validator.activation_eligibility_epoch == far_future_epoch &&
      validator.effective_balance == max_effective_balance
  end

  @doc """
  Check if ``validator`` is eligible for activation.
  """
  @spec eligible_for_activation?(BeaconState.t(), Validator.t()) :: boolean
  def eligible_for_activation?(%BeaconState{} = state, %Validator{} = validator) do
    far_future_epoch = Constants.far_future_epoch()

    validator.activation_eligibility_epoch <= state.finalized_checkpoint.epoch &&
      validator.activation_epoch == far_future_epoch
  end

  @doc """
  If the beacon chain has not managed to finalise a checkpoint for MIN_EPOCHS_TO_INACTIVITY_PENALTY epochs
  (that is, four epochs), then the chain enters the inactivity leak.
  """
  @spec in_inactivity_leak?(BeaconState.t()) :: boolean
  def in_inactivity_leak?(%BeaconState{} = state) do
    min_epochs_to_inactivity_penalty = ChainSpec.get("MIN_EPOCHS_TO_INACTIVITY_PENALTY")
    Accessors.get_finality_delay(state) > min_epochs_to_inactivity_penalty
  end

  @doc """
  Return whether ``flags`` has ``flag_index`` set.
  """
  @spec has_flag(Types.participation_flags(), integer) :: boolean
  def has_flag(participation_flags, flag_index) do
    flag = 1 <<< flag_index
    (participation_flags &&& flag) === flag
  end

  @doc """
  Check if ``data_1`` and ``data_2`` are slashable according to Casper FFG rules.
  """
  @spec slashable_attestation_data?(Types.AttestationData.t(), Types.AttestationData.t()) ::
          boolean
  def slashable_attestation_data?(data_1, data_2) do
    (data_1 != data_2 and data_1.target.epoch == data_2.target.epoch) or
      (data_1.source.epoch < data_2.source.epoch and data_2.target.epoch < data_1.target.epoch)
  end

  @doc """
  Check if ``validator`` is slashable.
  """
  @spec slashable_validator?(Validator.t(), Types.epoch()) :: boolean
  def slashable_validator?(validator, epoch) do
    not validator.slashed and
      (validator.activation_epoch <= epoch and epoch < validator.withdrawable_epoch)
  end

  @doc """
  Check if slashing attestation indices are in range of validators.
  """
  @spec indices_available?(any(), list(Types.validator_index())) :: boolean
  def indices_available?(validators, indices) do
    indices_available?(validators, indices, true)
  end

  defp indices_available?(_validators, [], true) do
    true
  end

  defp indices_available?(_validators, _indices, false) do
    false
  end

  defp indices_available?(validators, [h | indices], _acc) do
    indices_available?(validators, indices, h < validators)
  end

  @doc """
  Check if merkle branch is valid
  """
  @spec valid_merkle_branch?(
          Types.bytes32(),
          list(Types.bytes32()),
          Types.uint64(),
          Types.uint64(),
          Types.root()
        ) :: boolean
  def valid_merkle_branch?(leaf, branch, depth, index, root) do
    root == generate_merkle_proof(leaf, branch, depth, index)
  end

  def generate_merkle_proof(leaf, branch, depth, index) do
    branch
    |> Enum.take(depth)
    |> Enum.with_index()
    |> Enum.reduce(leaf, fn {v, i}, value -> hash_merkle_node(v, value, index, i) end)
  end

  defp hash_merkle_node(value_1, value_2, index, i) do
    if div(index, 2 ** i) |> rem(2) == 1 do
      Hash.hash(value_1 <> value_2)
    else
      Hash.hash(value_2 <> value_1)
    end
  end

  @doc """
  Check if ``indexed_attestation`` is not empty, has sorted and unique indices and has a valid aggregate signature.
  """
  @spec valid_indexed_attestation?(BeaconState.t(), Types.IndexedAttestation.t()) :: boolean
  def valid_indexed_attestation?(state, indexed_attestation) do
    indices = indexed_attestation.attesting_indices

    if Enum.empty?(indices) or not uniq_and_sorted?(indices) do
      false
    else
      domain_type = Constants.domain_beacon_attester()
      epoch = indexed_attestation.data.target.epoch

      signing_root =
        Accessors.get_domain(state, domain_type, epoch)
        |> then(&Misc.compute_signing_root(indexed_attestation.data, &1))

      indices
      |> Stream.map(&state.validators[&1])
      |> Enum.map_reduce(true, fn
        nil, _ -> {nil, false}
        v, b -> {v.pubkey, b}
      end)
      |> then(fn {pks, b} ->
        b and Bls.fast_aggregate_valid?(pks, signing_root, indexed_attestation.signature)
      end)
    end
  end

  defp uniq_and_sorted?([]), do: true
  defp uniq_and_sorted?([a, b | _]) when a >= b, do: false
  defp uniq_and_sorted?([_ | tail]), do: uniq_and_sorted?(tail)
end
