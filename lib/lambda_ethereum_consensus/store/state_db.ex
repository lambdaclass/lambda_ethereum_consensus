defmodule LambdaEthereumConsensus.Store.StateDb do
  @moduledoc """
  Beacon node state storage.
  """
  require Logger
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.StateInfoByRoot
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.BeaconState
  alias Types.StateInfo

  @state_prefix "beacon_state"
  @state_block_prefix @state_prefix <> "block"
  @stateslot_prefix @state_prefix <> "slot"

  @spec store_state_info(StateInfo.t()) :: :ok
  def store_state_info(%StateInfo{} = state_info) do
    StateInfoByRoot.put(state_info.root, state_info)
    block_key = block_key(state_info.block_root)
    Db.put(block_key, state_info.root)

    # WARN: this overrides any previous mapping for the same slot
    slot_key = slot_key(state_info.beacon_state.slot)
    Db.put(slot_key, state_info.block_root)
  end

  @spec prune_states_older_than(non_neg_integer()) :: :ok | {:error, String.t()} | :not_found
  def prune_states_older_than(slot) do
    Logger.info("[StateDb] Pruning started.", slot: slot)
    last_finalized_key = slot |> slot_key()

    with {:ok, it} <- Db.iterate(),
         {:ok, @stateslot_prefix <> _slot, _value} <-
           Exleveldb.iterator_move(it, last_finalized_key),
         {:ok, slots_to_remove} <- get_slots_to_remove(it),
         :ok <- Exleveldb.iterator_close(it) do
      slots_to_remove |> Enum.each(&remove_state_by_slot/1)
      Logger.info("[StateDb] Pruning finished. #{length(slots_to_remove)} states removed.")
    end
  end

  @spec get_slots_to_remove(list(non_neg_integer()), :eleveldb.itr_ref()) ::
          {:ok, list(non_neg_integer())}
  defp get_slots_to_remove(slots_to_remove \\ [], iterator) do
    case Exleveldb.iterator_move(iterator, :prev) do
      {:ok, @stateslot_prefix <> <<slot::unsigned-size(64)>>, _root} ->
        [slot | slots_to_remove] |> get_slots_to_remove(iterator)

      _ ->
        {:ok, slots_to_remove}
    end
  end

  @spec remove_state_by_slot(non_neg_integer()) :: :ok | :not_found
  defp remove_state_by_slot(slot) do
    with {:ok, block_root} <- get_block_root_by_slot(slot),
         {:ok, state_root} <- get_state_root_by_block_root(block_root) do
      slot |> slot_key() |> Db.delete()
      block_root |> block_key() |> Db.delete()
      StateInfoByRoot.delete(state_root)
    end
  end

  @spec get_state_root_by_block_root(Types.root()) ::
          {:ok, Types.root()} | {:error, String.t()} | :not_found
  def get_state_root_by_block_root(block_root), do: block_root |> block_key() |> Db.get()

  @spec get_state_by_block_root(Types.root()) ::
          {:ok, StateInfo.t()} | {:error, String.t()} | :not_found
  def get_state_by_block_root(block_root) do
    with {:ok, state_root} <- get_state_root_by_block_root(block_root) do
      StateInfoByRoot.get(state_root)
    end
  end

  @spec get_latest_state() ::
          {:ok, StateInfo.t()} | {:error, String.t()} | :not_found
  def get_latest_state() do
    last_key = slot_key(0xFFFFFFFFFFFFFFFF)

    with {:ok, it} <- Db.iterate(),
         {:ok, _key, _value} <- Exleveldb.iterator_move(it, last_key),
         {:ok, @stateslot_prefix <> _slot, root} <- Exleveldb.iterator_move(it, :prev),
         :ok <- Exleveldb.iterator_close(it) do
      StateInfoByRoot.get(root)
    else
      {:ok, _key, _value} -> :not_found
      {:error, :invalid_iterator} -> :not_found
    end
  end

  @spec get_block_root_by_slot(Types.slot()) ::
          {:ok, Types.root()} | {:error, String.t()} | :not_found
  def get_block_root_by_slot(slot),
    do: slot |> slot_key() |> Db.get()

  @spec get_state_by_slot(Types.slot()) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_state_by_slot(slot) do
    # WARN: this will return the latest state received for the given slot
    with {:ok, block_root} <- get_block_root_by_slot(slot) do
      get_state_by_block_root(block_root)
    end
  end

  defp block_key(root), do: Utils.get_key(@state_block_prefix, root)
  defp slot_key(slot), do: Utils.get_key(@stateslot_prefix, slot)
end
