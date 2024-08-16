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
  alias Types.BeaconState
  alias Types.Checkpoint
  alias Types.StateInfo

  @table :checkpoint_states

  def new() do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
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
    case :ets.lookup_element(@table, checkpoint, 2, :not_found) do
      :not_found -> compute_and_save(checkpoint)
      state -> {:ok, state}
    end
  end

  @spec put(Checkpoint.t(), BeaconState.t()) :: true
  def put(checkpoint, beacon_state) do
    :ets.insert(@table, {checkpoint, beacon_state})
  end

  # Computes the state for the checkpoint, adds it to the ets and returns it.
  @spec compute_and_save(Checkpoint.t()) :: {:ok, BeaconState.t()} | {:error, String.t()}
  defp compute_and_save(checkpoint) do
    with {:ok, state} <- compute_target_checkpoint_state(checkpoint.epoch, checkpoint.root) do
      put(checkpoint, state)
      {:ok, state}
    end
  end

  @doc """
  Calculate the state for a checkpoint without interacting with the db.

  DEPRECATED.
  """
  @deprecated "Use Store.get_checkpoint_state/2 instead"
  @spec compute_target_checkpoint_state(Types.epoch(), Types.root()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def compute_target_checkpoint_state(target_epoch, target_root) do
    target_slot = Misc.compute_start_slot_at_epoch(target_epoch)

    case BlockStates.get_state_info(target_root) do
      %StateInfo{beacon_state: state} ->
        if state.slot < target_slot do
          StateTransition.process_slots(state, target_slot)
        else
          {:ok, state}
        end

      nil ->
        {:error, "Checkpoint state for the target root not found"}
    end
  end
end
