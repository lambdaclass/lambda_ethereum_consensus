defmodule LambdaEthereumConsensus.StateTransition.Mutators do
  @moduledoc """
  Beacon State Mutators
  """

  alias SszTypes.BeaconState

  @doc """
  Increase the validator balance at index ``index`` by ``delta``.
  """
  @spec increase_balance(BeaconState.t(), SszTypes.validator_index(), SszTypes.gwei()) ::
          {:ok, BeaconState.t()}
  def increase_balance(%BeaconState{balances: balances} = state, index, delta) do
    new_balance = Enum.at(balances, index) + delta
    updated_balances = List.replace_at(balances, index, new_balance)

    updated_state = %{state | balances: updated_balances}
    {:ok, updated_state}
  end
end
