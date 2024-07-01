defmodule LambdaEthereumConsensus.Beacon.StoreSetup do
  @moduledoc """
  Logic to get an initial state, store and deposit contract snapshot from different sources.
  """

  alias LambdaEthereumConsensus.Beacon.CheckpointSync
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.StoreDb
  alias Types.DepositTreeSnapshot
  alias Types.Eth1Data
  alias Types.Store

  @type store_setup_strategy ::
          {:file, Types.BeaconState.t()} | {:checkpoint_sync_url, binary()} | :db

  require Logger

  @max_epochs_before_stale 8

  @doc """
  Args: at least one can be nil.
  - testnet_dir: directory of a testnet configuration, including ssz and yaml config.
  - checkpoint_sync_url: a url where checkpoint sync can be performed.

  Return value: a store setup strategy, which is one of the following:
  - {:file, anchor_state}: path of an ssz file to get the genesis state from.
  - {:checkpoint_sync_url, url}: url to get the genesis state from if performing checkpoint sync.
  - :db : the genesis state and store can only be recovered from the db.
  """
  def make_strategy!(nil, nil), do: :db
  def make_strategy!(nil, url) when is_binary(url), do: {:checkpoint_sync_url, url}

  def make_strategy!(dir, nil) when is_binary(dir) do
    Path.join(dir, "genesis.ssz")
    |> File.read!()
    |> SszEx.decode(Types.BeaconState)
    |> then(fn {:ok, state} -> {:file, state} end)
  end

  @doc """
  Gets a {store, genesis_validators_root} tuple with the configured strategy.
  """
  @spec setup!() :: Store.t()
  def setup!(), do: setup!(get_strategy!())

  @spec setup!(store_setup_strategy()) :: Store.t()
  def setup!({:file, anchor_state}) do
    Logger.info("[Store Setup] Setting up store from genesis file.")

    default_block = SszEx.default(Types.SignedBeaconBlock)
    state_root = Ssz.hash_tree_root!(anchor_state)
    anchor_block = %{default_block | message: %{default_block.message | state_root: state_root}}

    {:ok, store} = Store.get_forkchoice_store(anchor_state, anchor_block)
    store
  end

  def setup!({:checkpoint_sync_url, checkpoint_url}) do
    case restore_state_from_db() do
      {:ok, store} ->
        Logger.warning("[Checkpoint sync] Recent state found. Ignoring the checkpoint URL.")
        store

      _ ->
        fetch_state_from_url(checkpoint_url)
    end
  end

  def setup!(:db) do
    case restore_state_from_db() do
      nil ->
        Logger.error(
          "[Sync] No recent state found. Please specify the URL to fetch them from via the --checkpoint-sync-url flag"
        )

        Logger.flush()
        System.halt(1)

      {_, store} ->
        store
    end
  end

  @doc """
  Gets the deposit tree snapshot. Will return nil unless the strategy is checkpoint sync.
  """
  @spec get_deposit_snapshot!() :: DepositTreeSnapshot.t() | nil
  def get_deposit_snapshot!(), do: get_deposit_snapshot!(get_strategy!())

  @spec get_deposit_snapshot!(store_setup_strategy()) :: DepositTreeSnapshot.t() | nil
  def get_deposit_snapshot!({:checkpoint_sync_url, url}), do: fetch_deposit_snapshot(url)

  def get_deposit_snapshot!(:db) do
    case StoreDb.fetch_deposits_snapshot() do
      {:ok, snapshot} -> snapshot
      _ -> nil
    end
  end

  def get_deposit_snapshot!({:file, %{eth1_data: %Eth1Data{} = eth1_data}}) do
    if eth1_data.deposit_count == 0 do
      # TODO: parse block height from deploy_block.txt
      DepositTreeSnapshot.for_empty_tree(eth1_data.block_hash, 0)
    else
      nil
    end
  end

  @spec get_strategy!() :: store_setup_strategy
  defp get_strategy!() do
    Application.get_env(:lambda_ethereum_consensus, __MODULE__)
    |> Keyword.fetch!(:strategy)
  end

  defp restore_state_from_db() do
    # Try to fetch the old store from the database
    case StoreDb.fetch_store() do
      {:ok, %Store{finalized_checkpoint: %{epoch: finalized_epoch}} = store} ->
        if get_current_epoch(store) - finalized_epoch > @max_epochs_before_stale do
          Logger.info("[Sync] Found old state in DB.")
          {:old_state, store}
        else
          Logger.info("[Sync] Found recent state in DB.")
          {:ok, store}
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

        store

      _ ->
        Logger.error("[Checkpoint sync] Failed to fetch the latest finalized state and block")

        Logger.flush()
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

        Logger.flush()
        System.halt(1)
    end
  end
end
