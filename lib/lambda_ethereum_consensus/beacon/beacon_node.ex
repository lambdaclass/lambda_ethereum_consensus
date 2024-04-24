defmodule LambdaEthereumConsensus.Beacon.BeaconNode do
  @moduledoc false

  use Supervisor
  require Logger

  alias LambdaEthereumConsensus.Beacon.StoreSetup
  alias LambdaEthereumConsensus.ForkChoice.Helpers
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Validator
  alias Types.BeaconState

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    {store, genesis_validators_root} = StoreSetup.setup!()
    deposit_tree_snapshot = StoreSetup.get_deposit_snapshot!()

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

    validator_children =
      get_validator_children(deposit_tree_snapshot, head_slot, head_root, store.genesis_time)

    children =
      [
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
        LambdaEthereumConsensus.P2P.Gossip.BeaconBlock
      ] ++ validator_children

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp get_validator_children(nil, _, _, _) do
    Logger.warning("Deposit data not found. Validator will be disabled.")

    []
  end

  defp get_validator_children(snapshot, head_slot, head_root, genesis_time) do
    if is_nil(Application.get_env(:lambda_ethereum_consensus, Validator)) do
      []
    else
      %BeaconState{eth1_data_votes: votes} = BlockStates.get_state!(head_root)
      # TODO: move checkpoint sync outside and move this to application.ex
      [
        {Validator, {head_slot, head_root}},
        {LambdaEthereumConsensus.Execution.ExecutionChain, {genesis_time, snapshot, votes}}
      ]
    end
  end
end
