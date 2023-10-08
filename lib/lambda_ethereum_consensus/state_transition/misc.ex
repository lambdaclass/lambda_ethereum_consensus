defmodule LambdaEthereumConsensus.StateTransition.Misc do
  @moduledoc """
  Misc functions
  """

  @doc """
  Returns the epoch number at slot.
  """
  @spec compute_epoch_at_slot(integer()) :: integer()
  def compute_epoch_at_slot(slot) do
    div(slot, ChainSpec.get("SLOTS_PER_EPOCH"))
  end

  @doc """
  Returns the Unix timestamp at the start of the given slot
  """
  @spec compute_timestamp_at_slot(SszTypes.BeaconState, integer()) :: integer()
  def compute_timestamp_at_slot(state, slot) do
    # TODO: Here the 0 should be the GENESIS-SLOT
    slots_since_genesis = slot - 0
    state.genesis_time + slots_since_genesis * ChainSpec.get("SECONDS_PER_SLOT")
  end
end
