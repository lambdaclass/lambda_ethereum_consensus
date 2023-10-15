defmodule LambdaEthereumConsensus.StateTransition.Predicates do

  alias SszTypes.Validator

  @spec is_active_validator(Validator.t(), SszTypes.epoch()) :: boolean
  def is_active_validator(
        %Validator{activation_epoch: activation_epoch, exit_epoch: exit_epoch},
        epoch
      ) do
    activation_epoch <= epoch and epoch < exit_epoch
  end
end
