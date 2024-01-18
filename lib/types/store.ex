defmodule Types.Store do
  @moduledoc """
    The Store struct is used to track information required for the fork choice algorithm.
  """

  alias LambdaEthereumConsensus.ForkChoice.Tree
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.StateStore
  alias Types.BeaconBlock
  alias Types.BeaconState
  alias Types.Checkpoint
  alias Types.SignedBeaconBlock

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
    :unrealized_justifications,
    # Stores block data on the current fork tree (~last two epochs)
    :tree_cache
  ]

  @type t :: %__MODULE__{
          time: Types.uint64(),
          genesis_time: Types.uint64(),
          justified_checkpoint: Checkpoint.t() | nil,
          finalized_checkpoint: Checkpoint.t(),
          unrealized_justified_checkpoint: Checkpoint.t() | nil,
          unrealized_finalized_checkpoint: Checkpoint.t() | nil,
          proposer_boost_root: Types.root() | nil,
          equivocating_indices: MapSet.t(Types.validator_index()),
          blocks: %{Types.root() => BeaconBlock.t()},
          block_states: %{Types.root() => BeaconState.t()},
          checkpoint_states: %{Checkpoint.t() => BeaconState.t()},
          latest_messages: %{Types.validator_index() => Checkpoint.t()},
          unrealized_justifications: %{Types.root() => Checkpoint.t()},
          tree_cache: Tree.t()
        }

  @spec get_forkchoice_store(BeaconState.t(), SignedBeaconBlock.t(), boolean()) ::
          {:ok, t()} | {:error, String.t()}
  def get_forkchoice_store(
        %BeaconState{} = anchor_state,
        %SignedBeaconBlock{message: anchor_block} = signed_block,
        use_db
      ) do
    anchor_state_root = Ssz.hash_tree_root!(anchor_state)
    anchor_block_root = Ssz.hash_tree_root!(anchor_block)

    if anchor_block.state_root == anchor_state_root do
      anchor_epoch = Accessors.get_current_epoch(anchor_state)

      anchor_checkpoint = %Checkpoint{
        epoch: anchor_epoch,
        root: anchor_block_root
      }

      time = anchor_state.genesis_time + ChainSpec.get("SECONDS_PER_SLOT") * anchor_state.slot

      %__MODULE__{
        time: time,
        genesis_time: anchor_state.genesis_time,
        justified_checkpoint: anchor_checkpoint,
        finalized_checkpoint: anchor_checkpoint,
        unrealized_justified_checkpoint: anchor_checkpoint,
        unrealized_finalized_checkpoint: anchor_checkpoint,
        proposer_boost_root: <<0::256>>,
        equivocating_indices: MapSet.new(),
        blocks: %{},
        block_states: %{},
        checkpoint_states: %{anchor_checkpoint => anchor_state},
        latest_messages: %{},
        unrealized_justifications: %{anchor_block_root => anchor_checkpoint},
        tree_cache: Tree.new(anchor_block_root)
      }
      |> then(&if use_db, do: &1 |> Map.delete(:blocks) |> Map.delete(:block_states), else: &1)
      |> store_block(anchor_block_root, signed_block)
      |> store_state(anchor_block_root, anchor_state)
      |> then(&{:ok, &1})
    else
      {:error, "Anchor block state root does not match anchor state root"}
    end
  end

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
  def get_state(%__MODULE__{}, block_root) do
    case StateStore.get_state(block_root) do
      {:ok, state} -> state
      _ -> nil
    end
  end

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
    StateStore.store_state(state, block_root)
    store
  end

  @spec get_block(t(), Types.root()) :: BeaconBlock.t() | nil
  def get_block(%__MODULE__{blocks: blocks}, block_root) do
    Map.get(blocks, block_root)
  end

  @spec get_block(t(), Types.root()) :: BeaconBlock.t() | nil
  def get_block(%__MODULE__{}, block_root) do
    case Blocks.get_block(block_root) do
      nil -> nil
      signed_block -> signed_block.message
    end
  end

  @spec get_block!(t(), Types.root()) :: BeaconBlock.t()
  def get_block!(store, block_root) do
    case get_block(store, block_root) do
      nil -> raise "Block not found: 0x#{Base.encode16(block_root)}"
      v -> v
    end
  end

  @spec get_children(t(), Types.root()) :: [BeaconBlock.t()]
  def get_children(%__MODULE__{tree_cache: tree} = store, parent_root) do
    Tree.get_children!(tree, parent_root)
    |> Enum.map(&{&1, get_block!(store, &1)})
  end

  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  def store_block(%__MODULE__{blocks: blocks} = store, block_root, %{message: block}) do
    new_store = update_tree(store, block_root, block.parent_root)
    %{new_store | blocks: Map.put(blocks, block_root, block)}
  end

  @spec store_block(t(), Types.root(), SignedBeaconBlock.t()) :: t()
  def store_block(%__MODULE__{} = store, block_root, %SignedBeaconBlock{} = signed_block) do
    Blocks.store_block(block_root, signed_block)
    update_tree(store, block_root, signed_block.message.parent_root)
  end

  defp update_tree(%__MODULE__{} = store, block_root, parent_root) do
    # We expect the finalized block to be in the tree
    tree = Tree.update_root!(store.tree_cache, store.finalized_checkpoint.root)

    case Tree.add_block(tree, block_root, parent_root) do
      {:ok, new_tree} -> %{store | tree_cache: new_tree}
      # Block is older than current finalized block
      {:error, :not_found} -> store
    end
  end
end
