defmodule LambdaEthereumConsensus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {LambdaEthereumConsensus.Network, []},
      {LambdaEthereumConsensus.PeerConsumer, []},
      {LambdaEthereumConsensus.GossipConsumer,
       %{topic: "/eth2/bba4da96/beacon_block/ssz_snappy"}},
      {LambdaEthereumConsensus.GossipConsumer,
       %{topic: "/eth2/bba4da96/beacon_aggregate_and_proof/ssz_snappy"}},
      {LambdaEthereumConsensus.GossipConsumer,
       %{topic: "/eth2/bba4da96/beacon_attestation_0/ssz_snappy"}},
      {LambdaEthereumConsensus.GossipConsumer,
       %{topic: "/eth2/bba4da96/voluntary_exit/ssz_snappy"}},
      # {LambdaEthereumConsensus.GossipConsumer,
      #  %{topic: "/eth2/bba4da96/proposer_slashing/ssz_snappy"}},
      # {LambdaEthereumConsensus.GossipConsumer,
      #  %{topic: "/eth2/bba4da96/attester_slashing/ssz_snappy"}},
      {LambdaEthereumConsensus.GossipConsumer,
       %{topic: "/eth2/bba4da96/sync_committee_contribution_and_proof/ssz_snappy"}},
      {LambdaEthereumConsensus.GossipConsumer,
       %{topic: "/eth2/bba4da96/sync_committee_0/ssz_snappy"}},
      {LambdaEthereumConsensus.GossipConsumer,
       %{topic: "/eth2/bba4da96/bls_to_execution_change/ssz_snappy"}}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LambdaEthereumConsensus.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
