defmodule Types.Store do
  @moduledoc """
    The Store struct is used to track information required for the fork choice algorithm.
  """

  alias LambdaEthereumConsensus.ForkChoice.Head
  alias LambdaEthereumConsensus.ForkChoice.Simple.Tree
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Store.CheckpointStates
  alias Types.BeaconBlock
  alias Types.BeaconState
  alias Types.BlockInfo
  alias Types.Checkpoint
  alias Types.SignedBeaconBlock
  alias Types.StateInfo

  defstruct [
    :time,
    :genesis_time,
    :justified_checkpoint,
    :finalized_checkpoint,
    :unrealized_justified_checkpoint,
    :unrealized_finalized_checkpoint,
    :proposer_boost_root,
    :equivocating_indices,
    :latest_messages,
    :unrealized_justifications,
    :genesis_validators_root,
    :head_root,
    :head_slot,
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
          # NOTE: the `Checkpoint` values in latest_messages are `LatestMessage`s
          latest_messages: %{Types.validator_index() => Checkpoint.t()},
          unrealized_justifications: %{Types.root() => Checkpoint.t()},
          genesis_validators_root: Types.bytes32(),
          head_root: Types.root() | nil,
          head_slot: Types.slot() | nil,
          tree_cache: Tree.t()
        }

  @spec get_forkchoice_store(BeaconState.t(), SignedBeaconBlock.t()) ::
          {:ok, t()} | {:error, String.t()}
  def get_forkchoice_store(
        %BeaconState{} = anchor_state,
        %SignedBeaconBlock{message: anchor_block} = signed_block
      ) do
    block_info = BlockInfo.from_block(signed_block, :transitioned)
    {:ok, state_info} = StateInfo.from_beacon_state(anchor_state, block_root: block_info.root)
    anchor_block_root = block_info.root
    anchor_state_root = state_info.root

    if anchor_block.state_root == anchor_state_root do
      anchor_epoch = Accessors.get_current_epoch(anchor_state)

      anchor_checkpoint = %Checkpoint{
        epoch: anchor_epoch,
        root: anchor_block_root
      }

      time = anchor_state.genesis_time + ChainSpec.get("SECONDS_PER_SLOT") * anchor_state.slot

      BlockStates.store_state_info(state_info)
      CheckpointStates.put(anchor_checkpoint, anchor_state)

      %__MODULE__{
        time: time,
        genesis_time: anchor_state.genesis_time,
        justified_checkpoint: anchor_checkpoint,
        finalized_checkpoint: anchor_checkpoint,
        unrealized_justified_checkpoint: anchor_checkpoint,
        unrealized_finalized_checkpoint: anchor_checkpoint,
        proposer_boost_root: <<0::256>>,
        equivocating_indices: MapSet.new(),
        latest_messages: %{},
        unrealized_justifications: %{anchor_block_root => anchor_checkpoint},
        genesis_validators_root: ChainSpec.get_genesis_validators_root(),
        head_root: nil,
        head_slot: nil,
        tree_cache: Tree.new(anchor_block_root)
      }
      |> store_block_info(block_info)
      |> update_head_info()
      |> then(&{:ok, &1})
    else
      {:error, "Anchor block state root does not match anchor state root"}
    end
  end

  def get_current_slot(%__MODULE__{time: time, genesis_time: genesis_time}) do
    # NOTE: this assumes GENESIS_SLOT == 0
    div(time - genesis_time, ChainSpec.get("SECONDS_PER_SLOT"))
  end

  def get_current_epoch(store) do
    store |> get_current_slot() |> Misc.compute_epoch_at_slot()
  end

  def get_ancestor(%__MODULE__{} = store, root, slot) do
    block = Blocks.get_block!(root)

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

  @spec has_block?(t(), Types.root()) :: boolean()
  def has_block?(%__MODULE__{tree_cache: tree}, block_root) do
    Tree.has_block?(tree, block_root)
  end

  @spec get_children(t(), Types.root()) :: [BeaconBlock.t()]
  def get_children(%__MODULE__{tree_cache: tree}, parent_root) do
    Tree.get_children!(tree, parent_root)
    |> Enum.map(&{&1, Blocks.get_block!(&1)})
  end

  @spec store_block_info(t(), BlockInfo.t()) :: t()
  def store_block_info(%__MODULE__{} = store, %BlockInfo{} = block_info) do
    Blocks.store_block_info(block_info)
    update_tree(store, block_info.root, block_info.signed_block.message.parent_root)
  end

  @spec get_safe_execution_payload_hash(t()) :: Types.hash32()
  def get_safe_execution_payload_hash(%__MODULE__{} = store) do
    safe_block_root = get_safe_beacon_block_root(store)
    safe_block = Blocks.get_block!(safe_block_root)
    safe_block.body.execution_payload.block_hash
  end

  @spec get_safe_beacon_block_root(t()) :: Types.root()
  defp get_safe_beacon_block_root(%__MODULE__{} = store) do
    store.finalized_checkpoint.root
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

  defp update_head_info(store) do
    {:ok, head_root} = Head.get_head(store)
    %{slot: head_slot} = Blocks.get_block!(head_root)
    %{store | head_root: head_root, head_slot: head_slot}
  end
end
