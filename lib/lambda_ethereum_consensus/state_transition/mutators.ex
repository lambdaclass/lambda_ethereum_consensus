defmodule LambdaEthereumConsensus.StateTransition.Mutators do
  @moduledoc """
  This module contains utility functions for handling mutators
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState
  alias SszTypes.Validator

  @doc """
    Initiate the exit of the validator with index ``index``.
  """
  @spec initiate_validator_exit(BeaconState.t(), SszTypes.validator_index()) :: BeaconState.t()
  def initiate_validator_exit(state, index) do
    %BeaconState{validators: validators} = state

    if Enum.at(validators, index) != Constants.far_future_epoch() do
      :end
    end

    exit_epochs =
      for v <- validators, v.exit_epoch != Constants.far_future_epoch(), do: v.exit_epoch

    exit_queue_epoch =
      Enum.max(
        exit_epochs ++ [Misc.compute_activation_exit_epoch(Accessors.get_current_epoch(state))]
      )

    exit_queue_churn =
      Enum.filter(validators, fn v -> v.exit_epoch != Constants.far_future_epoch() end)

    if exit_queue_churn >= Accessors.get_validator_churn_limit(state) do
      exit_queue_epoch = exit_queue_epoch + 1
    end

    validator = Enum.at(validators, index)
    validator.exit_epoch = exit_queue_epoch

    validator.withdrawable_epoch =
      validator.exit_epoch + Constants.min_validator_withdrawability_delay()

    validators = List.replace_at(validators, index, validator)
    state.validators = validators

    state
  end
end
