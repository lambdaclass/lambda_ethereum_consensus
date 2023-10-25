defmodule LambdaEthereumConsensus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

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
      {LambdaEthereumConsensus.P2P.PeerConsumer, [host]},
      {LambdaEthereumConsensus.Libp2pPort, []},
      {LambdaEthereumConsensus.ForkChoice, {Keyword.get(args, :checkpoint_sync), host}},
      {LambdaEthereumConsensus.Beacon.PendingBlocks, [host]},
      {LambdaEthereumConsensus.P2P.GossipSub, [gsub]},
      # Start the Endpoint (http/https)
      BeaconApi.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LambdaEthereumConsensus.Supervisor]

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeaconApi.Endpoint.config_change(changed, removed)
    :ok
  end
end
