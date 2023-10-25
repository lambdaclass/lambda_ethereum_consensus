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
    Check if ``validator`` has an 0x01 prefixed "eth1" withdrawal credential.
  """
  @spec has_eth1_withdrawal_credential(Validator.t()) :: boolean
  def has_eth1_withdrawal_credential(%Validator{withdrawal_credentials: withdrawal_credentials}) do
    eth1_address_withdrawal_prefix = Constants.eth1_address_withdrawal_prefix()
    <<first_byte_of_withdrawal_credentials::binary-size(1), _::binary>> = withdrawal_credentials
    first_byte_of_withdrawal_credentials == eth1_address_withdrawal_prefix
  end

  @doc """
    Check if ``validator`` is fully withdrawable.
  """
  @spec is_fully_withdrawable_validator(Validator.t(), SszTypes.gwei(), SszTypes.epoch()) ::
          boolean
  def is_fully_withdrawable_validator(
        %Validator{withdrawable_epoch: withdrawable_epoch} = validator,
        balance,
        epoch
      ) do
    has_eth1_withdrawal_credential(validator) && withdrawable_epoch <= epoch && balance > 0
  end

  @doc """
    Check if ``validator`` is partially withdrawable.
  """
  @spec is_partially_withdrawable_validator(Validator.t(), SszTypes.gwei()) :: boolean
  def is_partially_withdrawable_validator(
        %Validator{effective_balance: effective_balance} = validator,
        balance
      ) do
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")
    has_max_effective_balance = effective_balance == max_effective_balance
    has_excess_balance = balance > max_effective_balance
    has_eth1_withdrawal_credential(validator) && has_max_effective_balance && has_excess_balance
  end
end
