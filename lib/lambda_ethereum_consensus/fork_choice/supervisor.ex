defmodule LambdaEthereumConsensus.ForkChoice do
  @moduledoc false

  use Supervisor
  require Logger

  alias LambdaEthereumConsensus.P2P.BlockDownloader
  alias LambdaEthereumConsensus.Utils

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init([checkpoint_url]) do
    case Utils.sync_from_checkpoint(checkpoint_url) do
      {:ok, %SszTypes.BeaconState{} = anchor_state} ->
        Logger.info("[Checkpoint sync] Received beacon state at slot #{anchor_state.slot}.")

        {:ok, anchor_block} = fetch_anchor_block(anchor_state)

        children = [
          {LambdaEthereumConsensus.ForkChoice.Store, {anchor_state, anchor_block}},
          {LambdaEthereumConsensus.ForkChoice.Tree, []}
        ]

        Supervisor.init(children, strategy: :one_for_all)

      {:error, _} ->
        :ignore
    end
  end

  def fetch_anchor_block(%SszTypes.BeaconState{} = anchor_state) do
    {:ok, state_root} = Ssz.hash_tree_root(anchor_state)

    # The latest_block_header.state_root was zeroed out to avoid circular dependencies
    {:ok, block_root} =
      Ssz.hash_tree_root(Map.put(anchor_state.latest_block_header, :state_root, state_root))

    case BlockDownloader.request_block_by_root(block_root) do
      {:ok, signed_block} ->
        Logger.info("[Checkpoint sync] Initial block fetched.")
        block = signed_block.message

        {:ok, block}

      {:error, message} ->
        Logger.error("[Checkpoint sync] Failed to fetch initial block: #{message}")
        fetch_anchor_block(anchor_state)
    end
  end
end
