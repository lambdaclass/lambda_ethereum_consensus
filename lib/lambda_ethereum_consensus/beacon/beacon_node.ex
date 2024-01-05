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
    case StateStore.get_latest_state() do
      {:ok, anchor_state} ->
        {:ok, anchor_block} = fetch_anchor_block(anchor_state)
        init_children(anchor_state, anchor_block)

      :not_found ->
        Logger.error(
          "[Sync] No initial state found. Please specify the URL to fetch it from via the --checkpoint-sync flag."
        )

        System.stop(1)
    end
  end

  def init([checkpoint_url]) do
    Logger.info("[Checkpoint sync] Initiating checkpoint sync.")

    case Task.await_many(
           [
             Task.async(fn -> CheckpointSync.get_last_finalized_state(checkpoint_url) end),
             Task.async(fn -> CheckpointSync.get_last_finalized_block(checkpoint_url) end)
           ],
           60_000
         ) do
      [
        {:ok, anchor_state},
        {:ok, anchor_block}
      ] ->
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

    time = :os.system_time(:second)

    children = [
      {LambdaEthereumConsensus.Beacon.BeaconChain, {anchor_state, time}},
      {LambdaEthereumConsensus.ForkChoice.Store, {anchor_state, anchor_block, time}},
      {LambdaEthereumConsensus.Beacon.PendingBlocks, []},
      {LambdaEthereumConsensus.Beacon.SyncBlocks, []},
      {LambdaEthereumConsensus.P2P.IncomingRequests, []},
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

    case BlockStore.get_block(block_root) do
      {:ok, anchor_block} ->
        {:ok, anchor_block}

      :not_found ->
        Logger.info("[Sync] Current block not found")
        {:error, :not_found}
    end
  end
end
