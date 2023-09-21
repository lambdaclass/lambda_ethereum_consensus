defmodule LambdaEthereumConsensus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    {:ok, host} = Libp2p.host_new()
    {:ok, gsub} = Libp2p.new_gossip_sub(host)

    children = [
      {LambdaEthereumConsensus.Store.Db, []},
      {LambdaEthereumConsensus.P2P.IncomingRequestHandler, [host]},
      {LambdaEthereumConsensus.P2P.PeerConsumer, [host]},
      {LambdaEthereumConsensus.P2P.GossipSub, [gsub]},
      {LambdaEthereumConsensus.Libp2pPort, []},
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

  defp get_initial_state do
    # Just for testing purposes
    %SszTypes.BeaconState{
      # https://github.com/eth-clients/eth2-networks/tree/master/shared/mainnet
      genesis_time: 1_606_824_023,
      genesis_validators_root:
        "4B363DB94E286120D76EB905340FDD4E54BFE9F06BF33FF6CF5AD27F511BFE95" |> Base.decode16!(),
      slot: 7_324_128,
      fork: nil,
      latest_block_header: nil,
      block_roots: nil,
      state_roots: nil,
      historical_roots: nil,
      eth1_data: nil,
      eth1_data_votes: nil,
      eth1_deposit_index: nil,
      validators: nil,
      balances: nil,
      randao_mixes: nil,
      slashings: nil,
      previous_epoch_participation: nil,
      current_epoch_participation: nil,
      justification_bits: nil,
      previous_justified_checkpoint: nil,
      current_justified_checkpoint: nil,
      finalized_checkpoint: nil,
      inactivity_scores: nil,
      current_sync_committee: nil,
      next_sync_committee: nil,
      latest_execution_payload_header: nil,
      next_withdrawal_index: nil,
      next_withdrawal_validator_index: nil,
      historical_summaries: nil
    }
  end
end
