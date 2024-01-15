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
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Store.BlockStore
  alias Types.BeaconState
  alias Types.SignedBeaconBlock

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

  @spec get_state(t(), Types.root()) :: BeaconState.t() | nil
  def get_state(%__MODULE__{block_states: states}, block_root) do
    Map.get(states, block_root)
  end

  @spec get_state(t(), Types.root()) :: BeaconState.t() | nil
  def get_state(%__MODULE__{}, block_root), do: BlockStates.get_state(block_root)

  @spec get_state!(t(), Types.root()) :: BeaconState.t()
  def get_state!(store, block_root) do
    case get_state(store, block_root) do
      nil -> raise "State not found for block #{block_root}"
      v -> v
    end
  end

  @spec store_state(t(), Types.root(), BeaconState.t()) :: t()
  def store_state(%__MODULE__{block_states: states} = store, block_root, state) do
    states
    |> Map.put(block_root, state)
    |> then(&%{store | block_states: &1})
  end

  @spec store_state(t(), Types.root(), BeaconState.t()) :: t()
  def store_state(%__MODULE__{} = store, block_root, state) do
    BlockStates.store_state(block_root, state)
    store
  end

  @spec get_block(t(), Types.root()) :: Types.BeaconBlock.t() | nil
  def get_block(%__MODULE__{blocks: blocks}, block_root) do
    Map.get(blocks, block_root)
  end

  @spec get_block(t(), Types.root()) :: Types.BeaconBlock.t() | nil
  def get_block(%__MODULE__{}, block_root) do
    case Blocks.get_block(block_root) do
      nil -> nil
      signed_block -> signed_block.message
    end
  end

  @spec get_block!(t(), Types.root()) :: Types.BeaconBlock.t()
  def get_block!(store, block_root) do
    case get_block(store, block_root) do
      nil -> raise "Block not found: 0x#{Base.encode16(block_root)}"
      v -> v
    end
  end

  @spec get_blocks(t()) :: Enumerable.t(Types.BeaconBlock.t())
  def get_blocks(%__MODULE__{blocks: blocks}), do: blocks
  def get_blocks(%__MODULE__{}), do: BlockStore.stream_blocks()

  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  def store_block(%__MODULE__{blocks: blocks} = store, block_root, %{message: block}) do
    blocks
    |> Map.put(block_root, block)
    |> then(&%{store | blocks: &1})
  end

  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  def store_block(%__MODULE__{} = store, block_root, %SignedBeaconBlock{} = signed_block) do
    Blocks.store_block(block_root, signed_block)
    store
  end
end
