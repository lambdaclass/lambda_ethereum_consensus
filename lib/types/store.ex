defmodule Types.Store do
  @moduledoc """
    The Store struct is used to track information required for the fork choice algorithm.
  """
  require Logger

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.ForkChoice.Head
  alias LambdaEthereumConsensus.ForkChoice.Simple.Tree
  alias LambdaEthereumConsensus.StateTransition
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

  # Suppress opaque-type warning: MapSet.new() in struct literal is seen through by dialyzer.
  @dialyzer {:no_opaque, get_forkchoice_store: 2}

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
    :head_root,
    :head_slot,
    # Stores block data on the current fork tree (~last two epochs)
    :tree_cache,

    ### Everything under this can be thought as cache for the db.
    # States indexed by block root.
    :states,
    # States indexed by checkpoint. Sometimes necessary because of empty slots.
    :checkpoint_states
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
          head_root: Types.root() | nil,
          head_slot: Types.slot() | nil,
          tree_cache: Tree.t(),
          states: %{Types.root() => StateInfo.t()},
          checkpoint_states: %{Types.Checkpoint.t() => BeaconState.t()}
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
        head_root: nil,
        head_slot: nil,
        tree_cache: Tree.new(anchor_block_root),
        states: %{},
        checkpoint_states: %{}
      }
      |> store_block_info(block_info)
      |> store_state(block_info.root, state_info)
      |> update_head_info()
      |> then(&{:ok, &1})
    else
      {:error, "Anchor block state root does not match anchor state root"}
    end
  end

  # We probably want to move this to a more appropriate module
  def get_current_epoch(store) do
    store |> ForkChoice.get_current_slot() |> Misc.compute_epoch_at_slot()
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

  @spec get_children(t(), Types.root()) :: [{Types.root(), BeaconBlock.t()}]
  def get_children(%__MODULE__{tree_cache: tree}, parent_root) do
    case Tree.get_children(tree, parent_root) do
      {:ok, children} ->
        Enum.map(children, &{&1, Blocks.get_block!(&1)})

      {:error, :not_found} ->
        Logger.warning(
          "[Store] Block #{Base.encode16(parent_root)} not found in tree during get_children"
        )

        []
    end
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

  @doc """
  Removes everything prior to the last finalized slot, specifically checkpoint states
  and states by root.
  """
  def prune(%__MODULE__{} = store) do
    new_finalized_slot =
      store.finalized_checkpoint.epoch * ChainSpec.get("SLOTS_PER_EPOCH")

    store
    |> prune_checkpoint_states(new_finalized_slot)
    |> prune_states(new_finalized_slot)
  end

  @doc """
  Gets a StatInfo given a block root. Defaults to the DB if not present in the store.
  """
  def get_state(store, root) when is_binary(root) do
    with nil <- Map.get(store.states, root) do
      BlockStates.get_state_info(root)
    end
  end

  def get_state!(store, root) do
    %StateInfo{} = get_state(store, root)
  end

  def store_state(store, block_root, state) do
    update_in(store.states, fn states -> Map.put(states, block_root, state) end)
  end

  @spec get_checkpoint_state(t(), Types.Checkpoint.t()) :: {t(), BeaconState.t() | nil}
  @doc """
  Gets a State given a checkpoint. If there is no state for that checkpoint in the store
  it will try to compute it.

  Computing the state means:
  1. Getting the state for the checkpoint's root.
  2. If the state is the one requested, it is returned.
  3. If not, that means that there are empty slots, so slots are processed.

  Returns a {store, state} or {store, nil}. The store may be updated if the state is calculated.
  """
  def get_checkpoint_state(store, %Checkpoint{} = checkpoint) do
    case Map.get(store.checkpoint_states, checkpoint) do
      nil -> compute_checkpoint_state(store, checkpoint)
      state -> {store, state}
    end
  end

  def remove_cache(%__MODULE__{} = store) do
    store |> Map.put(:states, %{}) |> Map.put(:checkpoint_states, %{})
  end

  defp prune_checkpoint_states(store, slot) do
    update_in(store.checkpoint_states, fn checkpoint_states ->
      Map.reject(checkpoint_states, fn {_checkpoint, state} -> state.slot < slot end)
    end)
  end

  defp prune_states(store, slot) do
    update_in(store.states, fn states ->
      Map.reject(states, fn {_root, %StateInfo{beacon_state: state}} -> state.slot < slot end)
    end)
  end

  @spec get_safe_beacon_block_root(t()) :: Types.root()
  defp get_safe_beacon_block_root(%__MODULE__{} = store) do
    store.finalized_checkpoint.root
  end

  defp update_tree(%__MODULE__{} = store, block_root, parent_root) do
    finalized_root = store.finalized_checkpoint.root

    tree =
      case Tree.update_root(store.tree_cache, finalized_root) do
        {:ok, pruned} ->
          pruned

        {:error, :not_found} ->
          # Tree is stale (e.g. after restart/recovery). Rebuild from finalized root.
          Logger.warning(
            "[Store] Finalized root #{Base.encode16(finalized_root)} not in tree, rebuilding"
          )

          Tree.new(finalized_root)
      end

    case Tree.add_block(tree, block_root, parent_root) do
      {:ok, new_tree} ->
        %{store | tree_cache: new_tree}

      {:error, :not_found} ->
        # Parent not in tree. Walk the parent chain from parent_root back to
        # the finalized root and add all intermediate blocks. This repairs the
        # tree after it was rebuilt with only the finalized root, or after
        # blocks were pruned but the chain wasn't maintained.
        repaired = repair_tree_chain(tree, finalized_root, parent_root)

        case Tree.add_block(repaired, block_root, parent_root) do
          {:ok, new_tree} -> %{store | tree_cache: new_tree}
          {:error, :not_found} -> %{store | tree_cache: repaired}
        end
    end
  end

  # Repair a tree by walking the parent chain from target_root back to
  # finalized_root and adding all intermediate blocks. This fills in gaps
  # when the tree only has the finalized root but blocks have been processed
  # beyond it (e.g., after a Tree.new rebuild or finalization advance).
  defp repair_tree_chain(tree, finalized_root, target_root) do
    chain = collect_parent_chain(target_root, finalized_root, [])

    if chain != [] do
      Logger.info("[Store] Repairing tree: adding #{length(chain)} blocks from parent chain")
    end

    Enum.reduce(chain, tree, fn {root, parent}, acc ->
      case Tree.add_block(acc, root, parent) do
        {:ok, t} -> t
        {:error, _} -> acc
      end
    end)
  end

  # Walk from current_root back to finalized_root, collecting {root, parent} pairs.
  # Returns the chain in order from finalized_root's child down to current_root.
  defp collect_parent_chain(current_root, finalized_root, acc)
       when current_root == finalized_root,
       do: acc

  defp collect_parent_chain(current_root, finalized_root, acc) do
    case Blocks.get_block_info(current_root) do
      %BlockInfo{signed_block: %{message: %{parent_root: parent}}} ->
        collect_parent_chain(parent, finalized_root, [{current_root, parent} | acc])

      _ ->
        # Can't walk further (block not found or pruned), return what we have
        Logger.warning(
          "[Store] Parent chain walk stopped at #{Base.encode16(current_root)}, " <>
            "#{length(acc)} blocks collected"
        )

        acc
    end
  end

  @spec update_head_info(t()) :: t()
  def update_head_info(store) do
    {:ok, head_root} = Head.get_head(store)
    %{slot: head_slot} = Blocks.get_block!(head_root)
    update_head_info(store, head_slot, head_root)
  end

  @spec update_head_info(t(), Types.slot(), Types.root()) :: t()
  def update_head_info(store, head_slot, head_root) do
    %{store | head_root: head_root, head_slot: head_slot}
  end

  defp compute_checkpoint_state(store, checkpoint) do
    target_slot = Misc.compute_start_slot_at_epoch(checkpoint.epoch)

    case get_state(store, checkpoint.root) do
      nil ->
        {store, nil}

      %StateInfo{beacon_state: state} ->
        if state.slot < target_slot do
          # The only way this can fail is if state.slot < target_slot, which is false by
          # construction.
          {:ok, new_state, _timings} = StateTransition.process_slots(state, target_slot)

          {update_in(store.checkpoint_states, fn s -> Map.put(s, checkpoint, new_state) end),
           new_state}
        else
          {store, state}
        end
    end
  end
end
