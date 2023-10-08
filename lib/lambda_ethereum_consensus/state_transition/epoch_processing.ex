defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  This module contains utility functions for handling epoch processing
  """

  alias ChainSpec
  alias SszTypes.BeaconState

  @spec process_eth1_data_reset(BeaconState.t()) :: BeaconState.t()
  def process_eth1_data_reset(state) do
    next_epoch = get_current_epoch(state) + 1
    epochs_per_eth1_voting_period = ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD")

    if rem(next_epoch, epochs_per_eth1_voting_period) == 0 do
      %BeaconState{state | eth1_data_votes: []}
    end

    state
  end

  @spec get_current_epoch(BeaconState.t()) :: SszTypes.epoch()
  defp get_current_epoch(%BeaconState{slot: slot} = _state) do
    # Return the current epoch.
    compute_epoch_at_slot(slot)
  end

  @spec compute_epoch_at_slot(SszTypes.slot()) :: SszTypes.epoch()
  defp compute_epoch_at_slot(slot) do
    # Return the epoch number at ``slot``.
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    div(slot, slots_per_epoch)
  end
end
