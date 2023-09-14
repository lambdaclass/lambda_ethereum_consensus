defmodule LambdaEthereumConsensus.Store.BeaconState do
  @moduledoc """
  Beacon node state storage.
  """
  alias SszTypes.BeaconState
  use Agent

  def start_link(opts) do
    initial_state = Keyword.get(opts, :initial_state, nil)
    Agent.start_link(fn -> initial_state end, name: __MODULE__)
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
