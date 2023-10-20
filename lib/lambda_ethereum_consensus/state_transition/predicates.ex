defmodule LambdaEthereumConsensus.StateTransition.Predicates do
  @moduledoc """
  Predicates functions
  """

  alias SszTypes.BeaconState
  alias SszTypes.Validator

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
end
