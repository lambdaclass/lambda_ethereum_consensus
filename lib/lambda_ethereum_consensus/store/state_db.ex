defmodule LambdaEthereumConsensus.Store.StateDb do
  @moduledoc """
  This module offers an interface to manage Beacon node state storage.

  The module coordinates the interaction with the following key-value stores:
    * `StateInfoByRoot` - Maps state roots to states.
    * `StateRootByBlockRoot` - Maps block roots to state roots.
    * `BlockRootBySlot` - Maps slots to block roots.
  """
  require Logger
  alias LambdaEthereumConsensus.Store.StateDb.BlockRootBySlot
  alias LambdaEthereumConsensus.Store.StateDb.StateInfoByRoot
  alias LambdaEthereumConsensus.Store.StateDb.StateRootByBlockRoot
  alias Types.BeaconState
  alias Types.StateInfo

  ##########################
  ### Public API
  ##########################

  @spec store_state_info(StateInfo.t()) :: :ok
  def store_state_info(%StateInfo{} = state_info) do
    StateInfoByRoot.put(state_info.root, state_info)
    StateRootByBlockRoot.put(state_info.block_root, state_info.root)
    # WARN: this overrides any previous mapping for the same slot
    BlockRootBySlot.put(state_info.beacon_state.slot, state_info.block_root)
  end

  @spec get_state_by_block_root(Types.root()) ::
          {:ok, StateInfo.t()} | {:error, String.t()} | :not_found
  def get_state_by_block_root(block_root) do
    with {:ok, state_root} <- StateRootByBlockRoot.get(block_root) do
      StateInfoByRoot.get(state_root)
    end
  end

  @spec get_state_by_state_root(Types.root()) ::
          {:ok, StateInfo.t()} | {:error, String.t()} | :not_found
  def get_state_by_state_root(state_root), do: StateInfoByRoot.get(state_root)

  @spec get_latest_state() ::
          {:ok, StateInfo.t()} | {:error, String.t()} | :not_found
  def get_latest_state() do
    with {:ok, last_block_root} <- BlockRootBySlot.get_last_slot_block_root(),
         {:ok, last_state_root} <- StateRootByBlockRoot.get(last_block_root) do
      StateInfoByRoot.get(last_state_root)
    end
  end

  @spec get_state_by_slot(Types.slot()) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_state_by_slot(slot) do
    # WARN: this will return the latest state received for the given slot
    with {:ok, block_root} <- BlockRootBySlot.get(slot) do
      get_state_by_block_root(block_root)
    end
  end

  @spec prune_states_older_than(non_neg_integer()) :: :ok | {:error, String.t()} | :not_found
  def prune_states_older_than(slot) do
    Logger.info("[StateDb] Pruning started.", slot: slot)

    result =
      BlockRootBySlot.fold_keys(slot, 0, fn slot, acc ->
        case BlockRootBySlot.get(slot) do
          {:ok, _block_root} ->
            remove_state_by_slot(slot)
            acc + 1

          other ->
            Logger.error(
              "[Block pruning] Failed to remove block from slot #{inspect(slot)}. Reason: #{inspect(other)}"
            )
        end
      end)

    # TODO: the separate get operation is avoided if we implement folding with values in KvSchema.
    case result do
      {:ok, n_removed} ->
        Logger.info("[StateDb] Pruning finished. #{inspect(n_removed)} states removed.")

      {:error, reason} ->
        Logger.error("[StateDb] Error pruning states: #{inspect(reason)}")
    end
  end

  ##########################
  ### Private Functions
  ##########################

  @spec remove_state_by_slot(non_neg_integer()) :: :ok | :not_found
  defp remove_state_by_slot(slot) do
    with {:ok, block_root} <- BlockRootBySlot.get(slot),
         {:ok, state_root} <- StateRootByBlockRoot.get(block_root) do
      BlockRootBySlot.delete(slot)
      StateRootByBlockRoot.delete(block_root)
      StateInfoByRoot.delete(state_root)
    end
  end
end
