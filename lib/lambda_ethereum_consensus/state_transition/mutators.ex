defmodule LambdaEthereumConsensus.StateTransition.Mutators do
  @moduledoc """
  Beacon State Mutators
  """

  alias SszTypes.BeaconState

  @doc """
  Increase the validator balance at index ``index`` by ``delta``.
  """
  @spec increase_balance(BeaconState.t(), SszTypes.validator_index(), SszTypes.gwei()) :: {:ok, BeaconState.t()}
  def increase_balance(state, index, delta) do
    balances = Map.get(state, :balances)
    new_balance = Enum.at(balances, index) + delta
    updated_balances = List.replace_at(balances, index, new_balance)
    
    Map.put(state, :balances, updated_balances)
    {:ok, state}
  end
end
