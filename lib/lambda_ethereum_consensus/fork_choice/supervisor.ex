defmodule LambdaEthereumConsensus.ForkChoice do
  @moduledoc false

  use Supervisor
  require Logger
  alias LambdaEthereumConsensus.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init({checkpoint_url, host}) do
    case Utils.sync_from_checkpoint(checkpoint_url) do
      {:ok, %SszTypes.BeaconState{} = initial_state} ->
        Logger.info("[Checkpoint sync] Received beacon state at slot #{initial_state.slot}.")

        children = [
          {LambdaEthereumConsensus.ForkChoice.Store, {initial_state, host}},
          {LambdaEthereumConsensus.ForkChoice.Tree, []}
        ]

        Supervisor.init(children, strategy: :one_for_all)

      {:error, _} ->
        :ignore
    end
  end
end
