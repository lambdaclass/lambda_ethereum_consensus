defmodule LambdaEthereumConsensus.Store.StateStore do
  @moduledoc """
  Beacon node state storage.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.BeaconState

  @state_prefix "beacon_state"
  @state_block_prefix "beacon_state_by_state"
  @stateslot_prefix @state_prefix <> "slot"

  @spec store_state(BeaconState.t()) :: :ok
  def store_state(%BeaconState{} = state) do
    # NOTE: due to how SSZ-hashing works, hash(block) == hash(header)
    block_root = Ssz.hash_tree_root!(state.latest_block_header)
    state_root = Ssz.hash_tree_root!(state)
    {:ok, encoded_state} = Ssz.to_ssz(state)

    key_block = state_key(block_root)
    key_state = block_key(state_root)
    Db.put(key_block, encoded_state)
    Db.put(key_state, key_block)

    # WARN: this overrides any previous mapping for the same slot
    slothash_key_block = root_by_slot_key(state.slot)
    Db.put(slothash_key_block, block_root)
  end

  defp get_block_root(root, type) do
    if type == :state_root do
      with {:ok, bin} <- root |> block_key() |> Db.get() do
        bin
      end
    else
      root
    end
  end

  @spec get_state(Types.root(), :block_root | :state_root) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_state(root, root_type) do
    with {:ok, bin} <- root |> get_block_root(root_type) |> state_key() |> Db.get() do
      Ssz.from_ssz(bin, BeaconState)
    end
  end

  @spec get_latest_state(:block_root | :state_root) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_latest_state(root_type) do
    last_key = root_by_slot_key(0xFFFFFFFFFFFFFFFF)

    with {:ok, it} <- Db.iterate(),
         {:ok, _key, _value} <- Exleveldb.iterator_move(it, last_key),
         {:ok, @state_prefix <> _slot, root} <- Exleveldb.iterator_move(it, :prev),
         :ok <- Exleveldb.iterator_close(it) do
      get_state(root, root_type)
    else
      {:ok, _key, _value} -> :not_found
      {:error, :invalid_iterator} -> :not_found
    end
  end

  @spec get_state_root_by_slot(Types.slot()) ::
          {:ok, Types.root()} | {:error, String.t()} | :not_found
  def get_state_root_by_slot(slot),
    do: slot |> root_by_slot_key() |> Db.get()

  @spec get_state_by_slot(Types.slot()) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_state_by_slot(slot) do
    # WARN: this will return the latest state received for the given slot
    with {:ok, root} <- get_state_root_by_slot(slot) do
      get_state(root, :block_root)
    end
  end

  defp state_key(root), do: Utils.get_key(@state_prefix, root)
  defp block_key(root), do: Utils.get_key(@state_block_prefix, root)
  defp root_by_slot_key(slot), do: Utils.get_key(@stateslot_prefix, slot)
end
