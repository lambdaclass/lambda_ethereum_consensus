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
end
