defmodule Types.Store do
  @moduledoc """
    The Store struct is used to track information required for the fork choice algorithm.
  """
  defstruct [
    :time,
    :genesis_time,
    :justified_checkpoint,
    :finalized_checkpoint,
    :unrealized_justified_checkpoint,
    :unrealized_finalized_checkpoint,
    :proposer_boost_root,
    :equivocating_indices,
    :blocks,
    :block_states,
    :checkpoint_states,
    :latest_messages,
    :unrealized_justifications
  ]

  @type t :: %__MODULE__{
          time: Types.uint64(),
          genesis_time: Types.uint64(),
          justified_checkpoint: Types.Checkpoint.t() | nil,
          finalized_checkpoint: Types.Checkpoint.t(),
          unrealized_justified_checkpoint: Types.Checkpoint.t() | nil,
          unrealized_finalized_checkpoint: Types.Checkpoint.t() | nil,
          proposer_boost_root: Types.root() | nil,
          equivocating_indices: MapSet.t(Types.validator_index()),
          blocks: %{Types.root() => Types.BeaconBlock.t()},
          block_states: %{Types.root() => Types.BeaconState.t()},
          checkpoint_states: %{Types.Checkpoint.t() => Types.BeaconState.t()},
          latest_messages: %{Types.validator_index() => Types.Checkpoint.t()},
          unrealized_justifications: %{Types.root() => Types.Checkpoint.t()}
        }

  alias LambdaEthereumConsensus.StateTransition.Misc

  def get_current_slot(%__MODULE__{time: time, genesis_time: genesis_time}) do
    # NOTE: this assumes GENESIS_SLOT == 0
    div(time - genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end

  def get_ancestor(%__MODULE__{} = store, root, slot) do
    block = get_block!(store, root)

    if block.slot > slot do
      get_ancestor(store, block.parent_root, slot)
    else
      root
    end
  end

  @doc """
  Compute the checkpoint block for epoch ``epoch`` in the chain of block ``root``
  """
  def get_checkpoint_block(%__MODULE__{} = store, root, epoch) do
    epoch_first_slot = Misc.compute_start_slot_at_epoch(epoch)
    get_ancestor(store, root, epoch_first_slot)
  end

  def get_state(%__MODULE__{} = store, block_root) do
    case Map.get(store.block_states, block_root) do
      nil -> :not_found
      v -> v
    end
  end

  def get_state!(store, block_root) do
    case get_state(store, block_root) do
      :not_found -> raise "State not found for block #{block_root}"
      v -> v
    end
  end

  def store_state(%__MODULE__{} = store, block_root, state) do
    store.block_states
    |> Map.put(block_root, state)
    |> then(&%{store | block_states: &1})
  end

  def get_block(%__MODULE__{} = store, block_root) do
    case Map.get(store.blocks, block_root) do
      nil -> :not_found
      v -> v
    end
  end

  def get_block!(store, block_root) do
    case get_block(store, block_root) do
      :not_found -> raise "Block not found: #{block_root}"
      v -> v
    end
  end

  def store_block(%__MODULE__{} = store, block_root, signed_block) do
    store.blocks
    |> Map.put(block_root, signed_block)
    |> then(&%{store | blocks: &1})
  end
end
