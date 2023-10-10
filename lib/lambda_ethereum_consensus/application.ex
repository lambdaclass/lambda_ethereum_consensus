defmodule LambdaEthereumConsensus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias LambdaEthereumConsensus.Store.StateStore
  alias LambdaEthereumConsensus.Utils

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Parse command line arguments
    {args, _remaining_args, _errors} =
      OptionParser.parse(System.argv(), switches: [checkpoint_sync: :string])

    {:ok, host} = Libp2p.host_new()
    {:ok, gsub} = Libp2p.new_gossip_sub(host)

    children = [
      {LambdaEthereumConsensus.Store.Db, []},
      {LambdaEthereumConsensus.P2P.Peerbook, []},
      {LambdaEthereumConsensus.P2P.IncomingRequestHandler, [host]},
      {LambdaEthereumConsensus.Beacon.PendingBlocks, [host]},
      {LambdaEthereumConsensus.P2P.PeerConsumer, [host]},
      {LambdaEthereumConsensus.P2P.GossipSub, [gsub]},
      {LambdaEthereumConsensus.Libp2pPort, []},
      {LambdaEthereumConsensus.ForkChoice.Tree, []},
      # Start the Endpoint (http/https)
      BeaconApi.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LambdaEthereumConsensus.Supervisor]

    with res = {:ok, _} <- Supervisor.start_link(children, opts) do
      # Check for the --checkpoint-sync argument and act accordingly
      # TODO: this could be done in an async task
      case Keyword.get(args, :checkpoint_sync) do
        nil ->
          :ok

        value ->
          case Utils.sync_from_checkpoint(value) do
            :error ->
              :ok

            state ->
              Logger.debug(
                "[Checkpoint sync] Received beacon state at slot #{state.slot}. Downloading blocks..."
              )

              StateStore.store_state(state)
          end
      end

      res
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeaconApi.Endpoint.config_change(changed, removed)
    :ok
  end
end
