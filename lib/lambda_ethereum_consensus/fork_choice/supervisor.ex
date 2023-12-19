defmodule LambdaEthereumConsensus.ForkChoice do
  @moduledoc false

  use Supervisor
  require Logger

  alias LambdaEthereumConsensus.ForkChoice.CheckpointSync
  alias LambdaEthereumConsensus.P2P.BlockDownloader
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
    Logger.info("[Sync] Initiating checkpoint sync.")

    case CheckpointSync.sync_from_checkpoint(checkpoint_url) do
      {:ok, %SszTypes.BeaconState{} = anchor_state} ->
        Logger.info("[Checkpoint sync] Received beacon state at slot #{anchor_state.slot}.")

        {:ok, anchor_block} = fetch_anchor_block(anchor_state)
        init_children(anchor_state, anchor_block)

      {:error, _} ->
        :ignore
    end
  end

  defp init_children(anchor_state, anchor_block) do
    Cache.initialize_tables()

    children = [
      {LambdaEthereumConsensus.ForkChoice.Store, {anchor_state, anchor_block}},
      {LambdaEthereumConsensus.ForkChoice.Tree, []}
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

  defp fetch_anchor_block(%SszTypes.BeaconState{} = anchor_state) do
    block_root = get_latest_block_hash(anchor_state)

    case BlockStore.get_block(block_root) do
      {:ok, anchor_block} ->
        {:ok, anchor_block}

      :not_found ->
        Logger.info("[Sync] Current block not found. Fetching from peers...")
        request_block_to_peers(block_root)
    end
  end

  defp request_block_to_peers(block_root) do
    case BlockDownloader.request_block_by_root(block_root) do
      {:ok, signed_block} ->
        Logger.info("[Sync] Initial block fetched.")
        {:ok, signed_block}

      {:error, message} ->
        Logger.warning("[Sync] Failed to fetch initial block: #{message}.\nRetrying...")
        request_block_to_peers(block_root)
    end
  end
end
