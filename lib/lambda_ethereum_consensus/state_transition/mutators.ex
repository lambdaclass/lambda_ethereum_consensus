defmodule LambdaEthereumConsensus.StateTransition.Mutators do
  alias SszTypes.BeaconState

  @spec decrease_balance(BeaconState.t(), integer(), SszTypes.gwei()) :: BeaconState.t()
  def decrease_balance(%BeaconState{balances: balances} = state, index, delta) do
    new_balance =
      if delta > Enum.at(balances, index) do
        0
      else
        Enum.at(balances, index) - delta
      end

    new_balances = List.replace_at(balances, index, new_balance)
    %BeaconState{state | balances: new_balances}
  end
end
