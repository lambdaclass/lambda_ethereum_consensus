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

  @doc """
  Process total slashing balances updates during epoch processing
  """
  @spec process_slashings_reset(BeaconState.t()) :: {:ok, BeaconState.t()} | {:error, binary()}
  def process_slashings_reset(
        %BeaconState{ slashings: slashings } = state
      ) do
    next_epoch = Accessors.get_current_epoch(state) + 1
    slashed_exit_length = ChainSpec.get("EPOCHS_PER_SLASHINGS_VECTOR")
    slashed_epoch = rem(next_epoch, slashed_exit_length)

    if length(slashings) != slashed_exit_length do
      {:error, "state slashing length #{length(slashings)} different than EpochsPerHistoricalVector #{slashed_exit_length}"}
    else
      new_slashings = List.replace_at(state.slashings, slashed_epoch, 0)
      new_state = %{state | slashings: new_slashings}
      {:ok, new_state}
    end
  end

end
