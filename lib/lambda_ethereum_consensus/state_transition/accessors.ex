defmodule LambdaEthereumConsensus.StateTransition.Accessors do
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias SszTypes.BeaconState

  @doc """
  Return the current epoch.
  """
  @spec get_current_epoch(BeaconState.t()) :: SszTypes.epoch()
  def get_current_epoch(%BeaconState{slot: slot} = _state) do
    Misc.compute_epoch_at_slot(slot)
  end
end
