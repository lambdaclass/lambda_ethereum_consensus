defmodule LambdaEthereumConsensus.Beacon.BeaconNode do
  @moduledoc false

  use Supervisor
  require Logger

  alias LambdaEthereumConsensus.Beacon.CheckpointSync
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.Store.{BlockStore, StateStore}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init([nil]) do
    with {:ok, anchor_state} <- StateStore.get_latest_state(:block_root),
         {:ok, anchor_block} <- fetch_anchor_block(anchor_state) do
      init_children(anchor_state, anchor_block)
    else
      {:error, reason} ->
        Logger.error("[Sync] Fetching from the database failed with: #{inspect(reason)}")

        System.stop(1)

      :not_found ->
        Logger.error(
          "[Sync] No initial state or block found. Please specify the URL to fetch them from via the --checkpoint-sync flag."
        )

        System.stop(1)
    end
  end

  def init([checkpoint_url]) do
    Logger.info("[Checkpoint sync] Initiating checkpoint sync.")

    case CheckpointSync.get_finalized_block_and_state(checkpoint_url) do
      {:ok, {anchor_state, anchor_block}} ->
        Logger.info(
          "[Checkpoint sync] Received beacon state and block at slot #{anchor_state.slot}."
        )

        init_children(anchor_state, anchor_block)

      _ ->
        Logger.error("[Checkpoint sync] Failed to fetch the latest finalized state and block.")

        System.stop(1)
    end
  end

  defp init_children(anchor_state, anchor_block) do
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

    children = [
      {LambdaEthereumConsensus.Beacon.BeaconChain, {anchor_state, time}},
      {LambdaEthereumConsensus.ForkChoice, {anchor_state, anchor_block, time}},
      {LambdaEthereumConsensus.Libp2pPort, libp2p_args},
      {LambdaEthereumConsensus.P2P.Peerbook, []},
      {LambdaEthereumConsensus.P2P.IncomingRequests, []},
      {LambdaEthereumConsensus.Beacon.PendingBlocks, []},
      {LambdaEthereumConsensus.Beacon.SyncBlocks, []},
      {LambdaEthereumConsensus.P2P.GossipSub, []}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp get_latest_block_hash(anchor_state) do
    state_root = Ssz.hash_tree_root!(anchor_state)
    # The latest_block_header.state_root was zeroed out to avoid circular dependencies
    anchor_state.latest_block_header
    |> Map.put(:state_root, state_root)
    |> Ssz.hash_tree_root!()
  end

  defp fetch_anchor_block(%Types.BeaconState{} = anchor_state) do
    block_root = get_latest_block_hash(anchor_state)
    BlockStore.get_block(block_root)
  end
end
