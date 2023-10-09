defmodule LambdaEthereumConsensus.StateTransition.Accessors do
  @moduledoc """
  Functions accessing the current BeaconState
  """

  alias LambdaEthereumConsensus.StateTransition.Misc

  @doc """
  Return the current epoch.
  """
  @spec get_current_epoch(SszTypes.BeaconState.t()) :: SszTypes.epoch()
  def get_current_epoch(state) do
    Misc.compute_epoch_at_slot(state.slot)
  end

  @doc """
  Return the randao mix at a recent epoch.
  """
  @spec get_randao_mix(SszTypes.BeaconState.t(), SszTypes.epoch()) :: <<_::256>>
  def get_randao_mix(state, epoch) do
    Enum.at(state.randao_mixes, rem(epoch, ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")))
  end
end
