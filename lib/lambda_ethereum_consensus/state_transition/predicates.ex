defmodule LambdaEthereumConsensus.StateTransition.Predicates do
  @moduledoc """
  Range of predicates enabling verification of state
  """

  alias LambdaEthereumConsensus.StateTransition.{Accessors, Misc}
  alias SszTypes.BeaconState
  alias SszTypes.Validator

  import Bitwise

  @doc """
  Check if ``validator`` is active.
  """
  @spec is_active_validator(Validator.t(), SszTypes.epoch()) :: boolean
  def is_active_validator(
        %Validator{activation_epoch: activation_epoch, exit_epoch: exit_epoch},
        epoch
      ) do
    activation_epoch <= epoch && epoch < exit_epoch
  end

  @doc """
  If the beacon chain has not managed to finalise a checkpoint for MIN_EPOCHS_TO_INACTIVITY_PENALTY epochs
  Check if ``validator`` is eligible to be placed into the activation queue.
  """
  @spec is_eligible_for_activation_queue(Validator.t()) :: boolean
  def is_eligible_for_activation_queue(%Validator{} = validator) do
    far_future_epoch = Constants.far_future_epoch()
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

    validator.activation_eligibility_epoch == far_future_epoch &&
      validator.effective_balance == max_effective_balance
  end

  @doc """
  Check if ``validator`` is eligible for activation.
  """
  @spec is_eligible_for_activation(BeaconState.t(), Validator.t()) :: boolean
  def is_eligible_for_activation(%BeaconState{} = state, %Validator{} = validator) do
    far_future_epoch = Constants.far_future_epoch()

    validator.activation_eligibility_epoch <= state.finalized_checkpoint.epoch &&
      validator.activation_epoch == far_future_epoch
  end

  @doc """
  If the beacon chain has not managed to finalise a checkpoint for MIN_EPOCHS_TO_INACTIVITY_PENALTY epochs
  (that is, four epochs), then the chain enters the inactivity leak.
  """
  @spec is_in_inactivity_leak(BeaconState.t()) :: boolean
  def is_in_inactivity_leak(%BeaconState{} = state) do
    min_epochs_to_inactivity_penalty = ChainSpec.get("MIN_EPOCHS_TO_INACTIVITY_PENALTY")
    Accessors.get_finality_delay(state) > min_epochs_to_inactivity_penalty
  end

  @doc """
  Return whether ``flags`` has ``flag_index`` set.
  """
  @spec has_flag(SszTypes.participation_flags(), integer) :: boolean
  def has_flag(participation_flags, flag_index) do
    flag = 2 ** flag_index
    (participation_flags &&& flag) === flag
  end

  @doc """
  Check if ``data_1`` and ``data_2`` are slashable according to Casper FFG rules.
  """
  @spec is_slashable_attestation_data(SszTypes.AttestationData.t(), SszTypes.AttestationData.t()) ::
          boolean
  def is_slashable_attestation_data(data_1, data_2) do
    (data_1 != data_2 and data_1.target.epoch == data_2.target.epoch) or
      (data_1.source.epoch < data_2.source.epoch and data_2.target.epoch < data_1.target.epoch)
  end

  @doc """
  Check if ``validator`` is slashable.
  """
  @spec is_slashable_validator(Validator.t(), SszTypes.epoch()) :: boolean
  def is_slashable_validator(validator, epoch) do
    not validator.slashed and
      (validator.activation_epoch <= epoch and epoch < validator.withdrawable_epoch)
  end

  @doc """
  Check if slashing attestation indices are in range of validators.
  """
  @spec is_indices_available(any(), list(SszTypes.validator_index())) :: boolean
  def is_indices_available(validators, indices) do
    is_indices_available(validators, indices, true)
  end

  defp is_indices_available(_validators, [], true) do
    true
  end

  defp is_indices_available(_validators, _indices, false) do
    false
  end

  defp is_indices_available(validators, [h | indices], _acc) do
    is_indices_available(validators, indices, h < validators)
  end

  @doc """
  Check if merkle branch is valid
  """
  @spec is_valid_merkle_branch?(
          SszTypes.bytes32(),
          list(SszTypes.bytes32()),
          SszTypes.uint64(),
          SszTypes.uint64(),
          SszTypes.root()
        ) :: boolean
  def is_valid_merkle_branch?(leaf, branch, depth, index, root) do
    root ==
      branch
      |> Enum.take(depth)
      |> Enum.with_index()
      |> Enum.reduce(leaf, fn {i, v}, value -> hash_merkle_node(v, value, index, i) end)
  end

  defp hash_merkle_node(value_1, value_2, index, i) do
    if rem(div(index, 2 ** i), 2) == 1 do
      :crypto.hash(:sha256, value_1 <> value_2)
    else
      :crypto.hash(:sha256, value_2 <> value_1)
    end
  end

  @doc """
  Check if ``indexed_attestation`` is not empty, has sorted and unique indices and has a valid aggregate signature.
  """
  @spec is_valid_indexed_attestation(BeaconState.t(), SszTypes.IndexedAttestation.t()) :: boolean
  def is_valid_indexed_attestation(state, indexed_attestation) do
    indices = indexed_attestation.attesting_indices

    if Enum.empty?(indices) or not (indices == indices |> Enum.uniq() |> Enum.sort()) do
      false
    else
      domain_type = Constants.domain_beacon_attester()
      epoch = indexed_attestation.data.target.epoch

      signing_root =
        Accessors.get_domain(state, domain_type, epoch)
        |> then(&Misc.compute_signing_root(indexed_attestation.data, &1))

      res =
        state.validators
        |> Stream.with_index()
        |> Stream.filter(fn {_, i} -> Enum.member?(indices, i) end)
        |> Enum.map(fn {%{pubkey: p}, _} -> p end)
        |> Bls.fast_aggregate_verify(signing_root, indexed_attestation.signature)

      case res do
        {:ok, r} -> r
        {:error, _} -> false
      end
    end
  end
end
