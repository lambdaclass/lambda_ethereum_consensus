defmodule LambdaEthereumConsensus.StateTransition.EpochProcessing do
  @moduledoc """
  This module contains utility functions for handling epoch processing
  """

  alias ChainSpec
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias SszTypes.BeaconState

  @spec process_eth1_data_reset(BeaconState.t()) :: {:ok, BeaconState.t()}
  def process_eth1_data_reset(state) do
    next_epoch = Accessors.get_current_epoch(state) + 1
    epochs_per_eth1_voting_period = ChainSpec.get("EPOCHS_PER_ETH1_VOTING_PERIOD")

    if rem(next_epoch, epochs_per_eth1_voting_period) == 0 do
      ^state = %BeaconState{state | eth1_data_votes: []}
    end

    {:ok, state}
  end
end
