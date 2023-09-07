defmodule LambdaEthereumConsensus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias LambdaEthereumConsensus.Utils

  use Application

  @impl true
  def start(_type, _args) do
    # Parse command line arguments
    {args, _remaining_args, _errors} =
      OptionParser.parse(System.argv(), switches: [checkpoint_sync: :string])

    # Check for the --checkpoint-sync argument and act accordingly
    case Keyword.get(args, :checkpoint_sync) do
      nil ->
        :ok

      value ->
        Utils.sync_from_checkpoint(value)
    end

    {:ok, host} = Libp2p.host_new()
    {:ok, gsub} = Libp2p.new_gossip_sub(host)

    children = [
      {LambdaEthereumConsensus.P2P.PeerConsumer, [host]},
      {LambdaEthereumConsensus.P2P.GossipSub, [gsub]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LambdaEthereumConsensus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
