defmodule LambdaEthereumConsensus.Beacon.BeaconNode do
  @moduledoc false

  use Supervisor
  require Logger

  alias LambdaEthereumConsensus.ForkChoice.Helpers
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.Store.Blocks

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {store, genesis_validators_root} =
      Application.get_env(:lambda_ethereum_consensus, ForkChoice)
      |> Keyword.fetch!(:genesis_state)
      |> Genesis.get_state!()

    Cache.initialize_cache()

    config = Application.fetch_env!(:lambda_ethereum_consensus, :discovery)
    port = Keyword.fetch!(config, :port)
    bootnodes = Keyword.fetch!(config, :bootnodes)

    libp2p_args = [
      listen_addr: [],
      enable_discovery: true,
      discovery_addr: "0.0.0.0:#{port}",
      bootnodes: bootnodes
    ]

    time = :os.system_time(:second)

    {:ok, head_root} = Helpers.get_head(store)
    %{slot: head_slot} = Blocks.get_block!(head_root)

    fork_choice_data = %{
      head_root: head_root,
      head_slot: head_slot,
      justified: store.justified_checkpoint,
      finalized: store.finalized_checkpoint
    }

    children = [
      {LambdaEthereumConsensus.Beacon.BeaconChain,
       {store.genesis_time, genesis_validators_root, fork_choice_data, time}},
      {LambdaEthereumConsensus.ForkChoice, {store, head_slot, time}},
      {LambdaEthereumConsensus.Libp2pPort, libp2p_args},
      LambdaEthereumConsensus.P2P.Peerbook,
      LambdaEthereumConsensus.P2P.IncomingRequests,
      LambdaEthereumConsensus.Beacon.PendingBlocks,
      LambdaEthereumConsensus.Beacon.SyncBlocks,
      LambdaEthereumConsensus.P2P.GossipSub,
      LambdaEthereumConsensus.P2P.Gossip.Attestation,
      # TODO: move checkpoint sync outside and move this to application.ex
      {LambdaEthereumConsensus.Validator, {head_slot, head_root}}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
