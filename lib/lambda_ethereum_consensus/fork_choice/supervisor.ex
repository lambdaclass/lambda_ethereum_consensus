defmodule LambdaEthereumConsensus.ForkChoice do
  use Supervisor
  require Logger
  alias LambdaEthereumConsensus.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Parse command line arguments
    {args, _remaining_args, _errors} =
      OptionParser.parse(System.argv(), switches: [checkpoint_sync: :string])

    Logger.notice("Syncing from checkpoint...")

    # Check for the --checkpoint-sync argument and act accordingly
    # TODO: this could be done in an async task
    {:ok, %SszTypes.BeaconState{} = initial_state} =
      Keyword.fetch!(args, :checkpoint_sync) |> Utils.sync_from_checkpoint()

    Logger.notice("[Checkpoint sync] Received beacon state at slot #{initial_state.slot}.")

    children = [
      {LambdaEthereumConsensus.ForkChoice.Store, [initial_state]},
      {LambdaEthereumConsensus.ForkChoice.Tree, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
