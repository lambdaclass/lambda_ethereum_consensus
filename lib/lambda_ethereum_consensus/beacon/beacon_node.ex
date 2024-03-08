defmodule LambdaEthereumConsensus.Beacon.BeaconNode do
  @moduledoc false

  use Supervisor
  require Logger

  alias LambdaEthereumConsensus.Beacon.CheckpointSync
  alias LambdaEthereumConsensus.ForkChoice.Helpers
  alias LambdaEthereumConsensus.StateTransition.Cache
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.StoreDb
  alias Types.Store

  @max_epochs_before_stale 8

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init([nil]) do
    case restore_state_from_db() do
      nil ->
        Logger.error(
          "[Sync] No recent state found. Please specify the URL to fetch them from via the --checkpoint-sync-url flag"
        )

        System.halt(1)

      {_, {store, root}} ->
        init_children(store, root)
    end
  end

  def init([checkpoint_url]) do
    case restore_state_from_db() do
      {:ok, {store, root}} ->
        Logger.warning("[Checkpoint sync] Recent state found. Ignoring the checkpoint URL.")
        init_children(store, root)

      _ ->
        fetch_state_from_url(checkpoint_url)
    end
  end

  defp init_children(%Store{} = store, genesis_validators_root) do
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
      # TODO: move checkpoint sync outside and move this to application.ex
      {LambdaEthereumConsensus.Validator, {head_slot, head_root}}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp restore_state_from_db do
    # Try to fetch the old store from the database
    case StoreDb.fetch_store() do
      {:ok, %Store{finalized_checkpoint: %{epoch: finalized_epoch}} = store} ->
        res = {store, ChainSpec.get_genesis_validators_root()}

        if get_current_epoch(store) - finalized_epoch > @max_epochs_before_stale do
          Logger.info("[Sync] Found old state in DB.")
          {:old_state, res}
        else
          Logger.info("[Sync] Found recent state in DB.")
          {:ok, res}
        end

      :not_found ->
        nil
    end
  end

  defp fetch_state_from_url(url) do
    Logger.info("[Checkpoint sync] Initiating checkpoint sync")

    genesis_validators_root = ChainSpec.get_genesis_validators_root()

    case CheckpointSync.get_finalized_block_and_state(url, genesis_validators_root) do
      {:ok, {anchor_state, anchor_block}} ->
        Logger.info(
          "[Checkpoint sync] Received beacon state and block",
          slot: anchor_state.slot
        )

        # We already checked block and state match
        {:ok, store} = Store.get_forkchoice_store(anchor_state, anchor_block)

        # Save store in DB
        StoreDb.persist_store(store)

        init_children(store, genesis_validators_root)

      _ ->
        Logger.error("[Checkpoint sync] Failed to fetch the latest finalized state and block")

        System.halt(1)
    end
  end

  defp get_current_epoch(store) do
    (:os.system_time(:second) - store.genesis_time)
    |> div(ChainSpec.get("SECONDS_PER_SLOT"))
    |> Misc.compute_epoch_at_slot()
  end
end
