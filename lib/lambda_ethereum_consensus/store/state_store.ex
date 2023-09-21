defmodule LambdaEthereumConsensus.Store.StateStore do
  @moduledoc """
  Beacon node state storage.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias SszTypes.BeaconState

  @state_prefix "beacon_state"
  @slot_prefix "slot"

  @spec store_state(BeaconState.t()) :: :ok
  def store_state(%BeaconState{} = state) do
    {:ok, state_root} = Ssz.hash_tree_root(state)
    {:ok, encoded_state} = Ssz.to_ssz(state)

    key = state_key(state_root)
    Db.put(key, encoded_state)

    # WARN: this overrides any previous mapping for the same slot
    slothash_key = state_root_by_slot_key(state.slot)
    Db.put(slothash_key, state_root)
  end

  @spec get_state(SszTypes.root()) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_state(root) do
    with {:ok, bin} <- root |> state_key() |> Db.get() do
      Ssz.from_ssz(bin, BeaconState)
    end
  end

  @spec get_state_root_by_slot(SszTypes.slot()) ::
          {:ok, SszTypes.root()} | {:error, String.t()} | :not_found
  def get_state_root_by_slot(slot),
    do: slot |> state_root_by_slot_key() |> Db.get()

  @spec get_state_by_slot(SszTypes.slot()) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_state_by_slot(slot) do
    # WARN: this will return the latest state received for the given slot
    with {:ok, root} <- get_state_root_by_slot(slot) do
      get_state(root)
    end
  end

  defp state_key(root), do: Utils.get_key(@state_prefix, root)
  defp state_root_by_slot_key(slot), do: Utils.get_key(@state_prefix <> @slot_prefix, slot)
end
