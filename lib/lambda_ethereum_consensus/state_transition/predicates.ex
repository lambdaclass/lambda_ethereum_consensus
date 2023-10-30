defmodule LambdaEthereumConsensus.StateTransition.Predicates do
  @moduledoc """
  Predicates functions
  """

  alias Bls
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias SszTypes.BeaconState
  alias SszTypes.IndexedAttestation
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
  Check if ``indexed_attestation`` is not empty, has sorted and unique indices and has a valid aggregate signature.
  """
  @spec is_valid_indexed_attestation(BeaconState.t(), IndexedAttestation.t()) ::
          {:ok, boolean} | {:error, binary()}
  def is_valid_indexed_attestation(
        %BeaconState{validators: validators} = state,
        indexed_attestation
      ) do
    # Verify indices are sorted and unique
    indices = indexed_attestation.attesting_indices

    sorted_indices =
      indices
      |> Enum.uniq()
      |> Enum.sort()

    # Verify aggregate signature
    case length(indices) != 0 && indices == sorted_indices do
      true ->
        pubkeys =
          Enum.map(indices, fn index ->
            v = Enum.at(validators, index)
            v.pubkey
          end)

        domain =
          Accessors.get_domain(
            state,
            Constants.domain_beacon_attester(),
            indexed_attestation.data.target.epoch
          )

        signing_root = Misc.compute_signing_root(indexed_attestation.data, domain)
        Bls.fast_aggregate_verify(pubkeys, signing_root, indexed_attestation.signature)

      false ->
        {:error, "Invalid"}
    end
  end
end
