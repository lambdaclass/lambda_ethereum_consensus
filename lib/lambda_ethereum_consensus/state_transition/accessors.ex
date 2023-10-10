defmodule LambdaEthereumConsensus.StateTransition.Accessors do
  @moduledoc """
  Functions accessing the current beacon state
  """

  alias ChainSpec
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias SszTypes.BeaconState

  @doc """
  Return the current epoch.
  """
  @spec get_current_epoch(BeaconState.t()) :: SszTypes.epoch()
  def get_current_epoch(%BeaconState{slot: slot} = _state) do
    Misc.compute_epoch_at_slot(slot)
  end

  @doc """
  Return the randao mix at a recent ``epoch``.
  """
  @spec get_randao_mix(BeaconState.t(), SszTypes.epoch()) :: SszTypes.bytes32()
  def get_randao_mix(%BeaconState{randao_mixes: randao_mixes} = _state, epoch) do
    epochs_per_historical_vector = ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")
    randao_mixes |> List.to_tuple() |> elem(rem(epoch, epochs_per_historical_vector))
  end
end
