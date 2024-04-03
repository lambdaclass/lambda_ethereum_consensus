defmodule Genesis do
  @moduledoc """
  Logic to get genesis state from different sources. Two strategies can be specified:
  - {:genesis_file, state}: a file with a hardcoded genesis is present.
  - {:checkpoint_sync_url, url}: getting a checkpoint state from a specified endpoint.
  - :db: The default one, which is relying on a saved state in the db.

  The order for processing is the following:
  - If a db state is present, it will always be used and the strategy will be ignored.
  - If no db state is present, the checkpoint_sync_url or genesis_file strategy will be used.
  - If the db is empty and the default strategy is used, there is no valid state to begin the chain
    from and the node will stop.

  All methods return {store, root} as that's what's needed by other modules such as
  the beacon node.
  """

  alias Types.SignedBeaconBlock
  alias Types.BeaconBlock
  alias Types.Store
  alias LambdaEthereumConsensus.SszEx
  require Logger

  @doc """
  Args:

  Opts are:
  - checkpoint_sync_url: url to get the genesis state from if performing checkpoint sync.
  - genesis_file: path of an ssz file to get the genesis state from.
  """

  def get_state!({:file, anchor_state}) do
    signed_anchor_block = %SignedBeaconBlock{
      message:
        SszEx.default(BeaconBlock) |> Map.put(:state_root, SszEx.hash_tree_root(anchor_state)),
      signature: SszEx.default()
    }

    {Store.get_forkchoice_store(anchor_state, signed_anchor_block),
     ChainSpec.get_genesis_validators_root()}
  end

  def get_state!({:checkpoint_sync_url, url}) do
    case restore_state_from_db() do
      {:ok, {store, root}} ->
        Logger.warning("[Checkpoint sync] Recent state found. Ignoring the checkpoint URL.")
        {store, root}

      _ ->
        fetch_state_from_url(checkpoint_url)
    end
  end

  def get_state!(:db) do
    case restore_state_from_db() do
      nil ->
        Logger.error(
          "[Sync] No recent state found. Please specify the URL to fetch them from via the --checkpoint-sync-url flag"
        )

        System.halt(1)

      {_, {store, root}} ->
        {store, root}
    end
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

        # TODO: integrate into CheckpointSync, and validate snapshot
        snapshot = fetch_deposit_snapshot(url)
        store = Store.init_deposit_tree(store, snapshot)

        # Save store in DB
        StoreDb.persist_store(store)

        {store, genesis_validators_root}

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

  defp fetch_deposit_snapshot(url) do
    case CheckpointSync.get_deposit_snapshot(url) do
      {:ok, snapshot} ->
        snapshot

      _ ->
        Logger.error("[Checkpoint sync] Failed to fetch the deposit snapshot")
        System.halt(1)
    end
  end
end
