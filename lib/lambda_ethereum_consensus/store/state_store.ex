defmodule LambdaEthereumConsensus.Store.StateStore do
  @moduledoc """
  Beacon node state storage.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias LambdaEthereumConsensus.Store.Utils
  alias Types.BeaconState

  @state_prefix_by_block "beacon_state_by_block"
  @state_prefix_by_state "beacon_state_by_state"
  @stateslot_prefix_by_block @state_prefix_by_block <> "slot"
  @stateslot_prefix_by_state @state_prefix_by_state <> "slot"

  @spec store_state(BeaconState.t()) :: :ok
  def store_state(%BeaconState{} = state) do
    # NOTE: due to how SSZ-hashing works, hash(block) == hash(header)
    block_root = Ssz.hash_tree_root!(state.latest_block_header)
    state_root = Ssz.hash_tree_root!(state)
    {:ok, encoded_state} = Ssz.to_ssz(state)

    key_block = state_key(block_root, :block_root)
    key_state = state_key(state_root, :state_root)
    Db.put(key_block, encoded_state)
    Db.put(key_state, encoded_state)

    # WARN: this overrides any previous mapping for the same slot
    slothash_key_block = root_by_slot_key(state.slot, :block_root)
    slothash_key_state = root_by_slot_key(state.slot, :state_root)
    Db.put(slothash_key_block, block_root)
    Db.put(slothash_key_state, state_root)
  end

  @spec get_state(Types.root(), :block_root | :state_root) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_state(root, root_type) do
    with {:ok, bin} <- root |> state_key(root_type) |> Db.get() do
      Ssz.from_ssz(bin, BeaconState)
    end
  end

  @spec get_latest_state(:block_root | :state_root) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_latest_state(root_type) do
    last_key = root_by_slot_key(0xFFFFFFFFFFFFFFFF, root_type)

    with {:ok, it} <- Db.iterate(),
         {:ok, _key, _value} <- Exleveldb.iterator_move(it, last_key),
         {:ok, _key, root} <- Exleveldb.iterator_move(it, :prev) |> validate_key_type(root_type),
         :ok <- Exleveldb.iterator_close(it) do
      get_state(root, root_type)
    else
      {:ok, _key, _value} -> :not_found
      {:error, :invalid_iterator} -> :not_found
    end
  end

  defp validate_key_type({:ok, key, root}, root_type) do
    valid_prefix =
      if root_type == :block_root,
        do: @stateslot_prefix_by_block,
        else: @stateslot_prefix_by_state

    <<prefix::binary-size(byte_size(valid_prefix)), _::binary>> = key
    if valid_prefix == prefix, do: {:ok, key, root}, else: {:error, :invalid_iterator}
  end

  @spec get_state_root_by_slot(Types.slot(), :block_root | :state_root) ::
          {:ok, Types.root()} | {:error, String.t()} | :not_found
  def get_state_root_by_slot(slot, root_type),
    do: slot |> root_by_slot_key(root_type) |> Db.get()

  @spec get_state_by_slot(Types.slot(), :block_root | :state_root) ::
          {:ok, BeaconState.t()} | {:error, String.t()} | :not_found
  def get_state_by_slot(slot, root_type) do
    # WARN: this will return the latest state received for the given slot
    with {:ok, root} <- get_state_root_by_slot(slot, root_type) do
      get_state(root, root_type)
    end
  end

  defp state_key(root, :block_root), do: Utils.get_key(@state_prefix_by_block, root)
  defp state_key(root, :state_root), do: Utils.get_key(@state_prefix_by_state, root)
  defp root_by_slot_key(slot, :block_root), do: Utils.get_key(@stateslot_prefix_by_block, slot)
  defp root_by_slot_key(slot, :state_root), do: Utils.get_key(@stateslot_prefix_by_state, slot)
end
