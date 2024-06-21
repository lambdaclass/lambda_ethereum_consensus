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
  alias LambdaEthereumConsensus.Store.KvSchema
  alias Types.BeaconState
  alias Types.Checkpoint

  use KvSchema, prefix: "checkpoint_states"

  @impl KvSchema
  @spec encode_key(Checkpoint.t()) :: {:ok, binary()} | {:error, binary()}
  def encode_key(checkpoint), do: Ssz.to_ssz(checkpoint)

  @impl KvSchema
  @spec decode_key(binary()) :: {:ok, Checkpoint.t()} | {:error, binary()}
  def decode_key(bin), do: Ssz.from_ssz(bin, Checkpoint)

  @impl KvSchema
  @spec encode_value(BeaconState.t()) :: {:ok, binary()} | {:error, binary()}
  def encode_value(state), do: Ssz.to_ssz(state)

  @impl KvSchema
  @spec decode_value(binary()) :: {:ok, BeaconState.t()} | {:error, binary()}
  def decode_value(bin), do: Ssz.from_ssz(bin, BeaconState)

  @doc """
  Gets the state for a checkpoint by getting the last block and processing slots until the checkpoint.
  If there's a block for that checkpoint no calculation will be made, the state for that block will be
  returned.

  The state is saved in the db so further calls to get the state for the same checkpoint will be a kv
  store get instead of a state transition.
  """
  @spec get_checkpoint_state(Checkpoint.t()) :: {:ok, BeaconState.t()} | {:error, binary()}
  def get_checkpoint_state(checkpoint) do
    case get(checkpoint) do
      {:ok, state} ->
        {:ok, state}

      :not_found ->
        with {:ok, state} <- compute_target_checkpoint_state(checkpoint.epoch, checkpoint.root) do
          put(checkpoint, state)
          {:ok, state}
        end
    end
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

  @doc """
  Deletes all checkpoint states prior to the finalized one passed by parameter.
  """
  @spec prune(Checkpoint.t()) :: :ok
  def prune(finalized_checkpoint) do
    Logger.info("Pruning old checkpoint states")

    case fold(finalized_checkpoint, 0, fn key, acc ->
           delete(key)
           acc + 1
         end) do
      {:ok, amount} ->
        Logger.info("Pruned #{amount} checkpoint states")

      {:error, reason} ->
        Logger.error("Error while pruning checkpoint states: #{inspect(reason)}")
    end
  end
end
