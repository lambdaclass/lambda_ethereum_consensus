defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  Update effective balances with hysteresis
  """

  alias ChainSpec
  alias SszTypes.BeaconState
  alias SszTypes.Validator

  @spec process_effective_balance_updates(BeaconState.t()) :: {:ok, BeaconState.t()}  |  {:error, binary() }
  def process_effective_balance_updates(
        %BeaconState{validators: validators, balances: balances} = state
      ) do
    effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")
    hysteresis_quotient = ChainSpec.get("HYSTERESIS_QUOTIENT")
    hysteresis_downward_multiplier = ChainSpec.get("HYSTERESIS_DOWNWARD_MULTIPLIER")
    hysteresis_upward_multiplier = ChainSpec.get("HYSTERESIS_UPWARD_MULTIPLIER")
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

    validators_with_index = validators |> Enum.with_index()

    new_validators =
      validators_with_index
      |> Enum.map(fn {%Validator{effective_balance: effective_balance} = validator, index} ->
        balance = balances[index]
        hysteresis_increment = div(effective_balance_increment, hysteresis_quotient)
        downward_threshold = hysteresis_increment * hysteresis_downward_multiplier
        upward_threshold = hysteresis_increment * hysteresis_upward_multiplier

        if balance + downward_threshold < effective_balance or
             effective_balance + upward_threshold < balance do
          new_effective_balance =
            min(balance - rem(balance, effective_balance_increment), max_effective_balance)

          %{validator | effective_balance: new_effective_balance}
        else
          validator
        end
      end)

    %BeaconState{state | validators: new_validators}
  end
end
