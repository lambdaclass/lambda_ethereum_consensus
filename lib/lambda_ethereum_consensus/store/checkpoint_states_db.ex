defmodule LambdaEthereumConsensus.Store.CheckpointStates do
  @moduledoc """
  Utilities to store and retrieve states that correspond to a checkpoint, regardless of the
  existence of a block for it. In the Consensus Specs, this is an attribute of the Fork Choice
  store.
  """

  require Logger
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Store.LRUCache
  alias Types.BeaconState
  alias Types.Checkpoint

  @table :checkpoint_states
  @max_entries 512
  @batch_prune_size 32

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start:
        {LRUCache, :start_link,
         [
           [
             table: @table,
             max_entries: @max_entries,
             batch_prune_size: @batch_prune_size,
             # We don't actually store this in the db, we either calculate it or
             # get it from the ets.
             store_func: fn _k, _v -> :ok end
           ]
         ]}
    }
  end

  @doc """
  Gets the state for a checkpoint by getting the last block and processing slots until the checkpoint.
  If there's a block for that checkpoint no calculation will be made, the state for that block will be
  returned.

  The state is saved in the db so further calls to get the state for the same checkpoint will be a kv
  store get instead of a state transition.
  """
  @spec get_checkpoint_state(Checkpoint.t()) :: {:ok, BeaconState.t()} | {:error, binary()}
  def get_checkpoint_state(checkpoint) do
    case LRUCache.get(
           @table,
           checkpoint,
           fn checkpoint -> compute_target_checkpoint_state(checkpoint.epoch, checkpoint.root) end
         ) do
      nil -> :not_found
      value -> {:ok, value}
    end
  end

  def put(checkpoint, beacon_state) do
    LRUCache.put(@table, checkpoint, beacon_state)
  end

  @doc """
  Calculate the state for a checkpoint without interacting with the db.
  """
  @spec compute_target_checkpoint_state(Types.epoch(), Types.root()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def compute_target_checkpoint_state(target_epoch, target_root) do
    target_slot = Misc.compute_start_slot_at_epoch(target_epoch)
    state = BlockStates.get_state_info!(target_root).beacon_state

    if state.slot < target_slot do
      StateTransition.process_slots(state, target_slot)
    else
      {:ok, state}
    end
  end
end
