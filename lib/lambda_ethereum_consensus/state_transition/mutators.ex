defmodule LambdaEthereumConsensus.StateTransition.Mutators do
  alias SszTypes.BeaconState

  @doc """
    Decrease the validator balance at index ``index`` by ``delta``, with underflow protection.
  """
  @spec decrease_balance(BeaconState.t(), SszTypes.validator_index(), SszTypes.gwei()) ::
          BeaconState.t()
  def decrease_balance(%BeaconState{balances: balances} = state, index, delta) do
    new_state =
      if delta > Enum.fetch!(balances, index) do
        %BeaconState{state | balances: List.replace_at(balances, index, 0)}
      else
        %BeaconState{
          state
          | balances: List.replace_at(balances, index, Enum.fetch!(balances, index) - delta)
        }
      end

    new_state
  end
end
