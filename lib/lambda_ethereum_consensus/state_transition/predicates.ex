defmodule LambdaEthereumConsensus.StateTransition.Predicates do
  @moduledoc """
  Predicates functions
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
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
end
