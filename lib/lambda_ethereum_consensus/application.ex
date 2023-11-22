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

    config = Application.fetch_env!(:lambda_ethereum_consensus, :discovery)
    port = Keyword.fetch!(config, :port)
    bootnodes = Keyword.fetch!(config, :bootnodes)

    libp2p_opts = [
      listen_addr: [],
      enable_discovery: true,
      discovery_addr: "0.0.0.0:#{port}",
      bootnodes: bootnodes
    ]

    children = [
      {LambdaEthereumConsensus.Telemetry, []},
      {LambdaEthereumConsensus.Libp2pPort, libp2p_opts},
      {LambdaEthereumConsensus.Store.Db, []},
      {LambdaEthereumConsensus.P2P.Peerbook, []},
      {LambdaEthereumConsensus.P2P.IncomingRequests, []},
      {LambdaEthereumConsensus.ForkChoice, [Keyword.get(args, :checkpoint_sync)]},
      {LambdaEthereumConsensus.Beacon.PendingBlocks, []},
      {LambdaEthereumConsensus.Beacon.SyncBlocks, []},
      {LambdaEthereumConsensus.P2P.GossipSub, []},
      # Start the Endpoint (http/https)
      {BeaconApi.Endpoint, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LambdaEthereumConsensus.Supervisor]

    result = Supervisor.start_link(children, opts)

    # Start scheduled tasks only when app started, to avoid
    # hogging resources while starting up
    case result do
      {:ok, _} -> start_scheduled_tasks()
      _ -> nil
    end

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeaconApi.Endpoint.config_change(changed, removed)
    :ok
  end

  defp start_scheduled_tasks do
    LambdaEthereumConsensus.P2P.Peerbook.schedule_pruning()
    LambdaEthereumConsensus.ForkChoice.Store.schedule_next_tick()
    LambdaEthereumConsensus.Beacon.PendingBlocks.schedule_blocks_processing()
    LambdaEthereumConsensus.Beacon.PendingBlocks.schedule_blocks_download()
  end
end
