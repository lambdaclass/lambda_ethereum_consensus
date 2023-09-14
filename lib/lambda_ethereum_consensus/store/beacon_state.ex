defmodule LambdaEthereumConsensus.Store.BeaconState do
  @moduledoc """
  Beacon node state storage.
  """
  alias SszTypes.BeaconState
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end

  @spec get_state() :: BeaconState.t() | nil
  def get_state do
    Agent.get(__MODULE__, & &1)
  end

  @spec set_state(BeaconState.t()) :: :ok
  def set_state(%BeaconState{} = new_state) do
    Agent.update(__MODULE__, fn _ -> new_state end)
  end
end
