defmodule LambdaEthereumConsensus.ForkChoice.Helpers do
  @moduledoc """
    Utility functions for the fork choice.
  """
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.StateTransition.{Accessors, Misc}
  alias LambdaEthereumConsensus.Store.BlockStore
  alias Types.BeaconState
  alias Types.Checkpoint
  alias Types.SignedBeaconBlock
  alias Types.Store

  @spec current_status_message(Store.t()) ::
          {:ok, Types.StatusMessage.t()} | {:error, any}
  def current_status_message(store) do
    with {:ok, head_root} <- get_head(store),
         state when not is_nil(state) <- Store.get_state(store, head_root) do
      {:ok,
       %Types.StatusMessage{
         fork_digest:
           Misc.compute_fork_digest(state.fork.current_version, state.genesis_validators_root),
         finalized_root: state.finalized_checkpoint.root,
         finalized_epoch: state.finalized_checkpoint.epoch,
         head_root: head_root,
         head_slot: state.slot
       }}
    else
      nil -> {:error, "Head state not found"}
    end
  end

  @spec get_forkchoice_store(BeaconState.t(), SignedBeaconBlock.t(), boolean()) ::
          {:ok, Store.t()} | {:error, String.t()}
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

      %Store{
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
        unrealized_justifications: %{anchor_block_root => anchor_checkpoint}
      }
      |> then(&if use_db, do: &1 |> Map.delete(:blocks) |> Map.delete(:block_states), else: &1)
      |> Store.store_block(anchor_block_root, signed_block)
      |> Store.store_state(anchor_block_root, anchor_state)
      |> then(&{:ok, &1})
    else
      {:error, "Anchor block state root does not match anchor state root"}
    end
  end

  @spec get_head(Store.t()) :: {:ok, Types.root()} | {:error, any}
  def get_head(%Store{} = store) do
    # Get filtered block tree that only includes viable branches
    blocks = get_filtered_block_tree(store)
    # Execute the LMD-GHOST fork choice
    head = store.justified_checkpoint.root

    # PERF: return just the parent root and the block root in `get_filtered_block_tree`
    Stream.cycle([nil])
    |> Enum.reduce_while(head, fn nil, head ->
      blocks
      |> Stream.filter(fn {_, block} -> block.parent_root == head end)
      |> Stream.map(fn {root, _} -> root end)
      # Ties broken by favoring block with lexicographically higher root
      |> Enum.sort(:desc)
      |> then(fn
        [] -> {:halt, head}
        c -> {:cont, Enum.max_by(c, &get_weight(store, &1))}
      end)
    end)
    |> then(&{:ok, &1})
  end

  defp get_weight(%Store{} = store, root) do
    state = Map.fetch!(store.checkpoint_states, store.justified_checkpoint)

    block = Store.get_block!(store, root)

    # PERF: use ``Aja.Vector.foldl``
    attestation_score =
      Accessors.get_active_validator_indices(state, Accessors.get_current_epoch(state))
      |> Stream.reject(&Aja.Vector.at!(state.validators, &1).slashed)
      |> Stream.filter(&Map.has_key?(store.latest_messages, &1))
      |> Stream.reject(&MapSet.member?(store.equivocating_indices, &1))
      |> Stream.filter(fn i ->
        Store.get_ancestor(store, store.latest_messages[i].root, block.slot) == root
      end)
      |> Stream.map(&Aja.Vector.at!(state.validators, &1).effective_balance)
      |> Enum.sum()

    if store.proposer_boost_root == <<0::256>> or
         Store.get_ancestor(store, store.proposer_boost_root, block.slot) != root do
      # Return only attestation score if ``proposer_boost_root`` is not set
      attestation_score
    else
      # Calculate proposer score if ``proposer_boost_root`` is set
      # Boost is applied if ``root`` is an ancestor of ``proposer_boost_root``
      committee_weight =
        Accessors.get_total_active_balance(state)
        |> div(ChainSpec.get("SLOTS_PER_EPOCH"))

      proposer_score = (committee_weight * ChainSpec.get("PROPOSER_SCORE_BOOST")) |> div(100)
      attestation_score + proposer_score
    end
  end

  # Retrieve a filtered block tree from ``store``, only returning branches
  # whose leaf state's justified/finalized info agrees with that in ``store``.
  defp get_filtered_block_tree(%Store{} = store) do
    base = store.justified_checkpoint.root
    {_, blocks} = filter_block_tree(store, base, %{})
    blocks
  end

  defp filter_block_tree(%Store{} = store, block_root, blocks) do
    block = Store.get_block!(store, block_root)

    # TODO: this is highly inefficient. We should move to `ForkChoice.Tree` ASAP
    children =
      Store.get_blocks(store)
      |> Stream.filter(fn {_, block} -> block.parent_root == block_root end)
      |> Enum.map(fn {root, _} -> root end)

    # If any children branches contain expected finalized/justified checkpoints,
    # add to filtered block-tree and signal viability to parent.
    {filter_block_tree_result, new_blocks} =
      Enum.map_reduce(children, blocks, fn root, acc -> filter_block_tree(store, root, acc) end)

    cond do
      Enum.any?(filter_block_tree_result) ->
        {true, Map.put(new_blocks, block_root, block)}

      not Enum.empty?(children) ->
        {false, new_blocks}

      true ->
        filter_leaf_block(store, block_root, block, blocks)
    end
  end

  defp filter_leaf_block(%Store{} = store, block_root, block, blocks) do
    current_epoch = store |> Store.get_current_slot() |> Misc.compute_epoch_at_slot()
    voting_source = get_voting_source(store, block_root)

    # The voting source should be at the same height as the store's justified checkpoint
    correct_justified =
      store.justified_checkpoint.epoch == Constants.genesis_epoch() or
        voting_source.epoch == store.justified_checkpoint.epoch

    # If the previous epoch is justified, the block should be pulled-up. In this case, check that unrealized
    # justification is higher than the store and that the voting source is not more than two epochs ago
    correct_justified =
      if not correct_justified and is_previous_epoch_justified(store) do
        store.unrealized_justifications[block_root].epoch >= store.justified_checkpoint.epoch and
          voting_source.epoch + 2 >= current_epoch
      else
        correct_justified
      end

    finalized_checkpoint_block =
      Store.get_checkpoint_block(
        store,
        block_root,
        store.finalized_checkpoint.epoch
      )

    correct_finalized =
      store.finalized_checkpoint.epoch == Constants.genesis_epoch() or
        store.finalized_checkpoint.root == finalized_checkpoint_block

    # If expected finalized/justified, add to viable block-tree and signal viability to parent.
    if correct_justified and correct_finalized do
      {true, Map.put(blocks, block_root, block)}
    else
      # Otherwise, branch not viable
      {false, blocks}
    end
  end

  # Compute the voting source checkpoint in event that block with root ``block_root`` is the head block
  def get_voting_source(%Store{} = store, block_root) do
    block = Store.get_block!(store, block_root)
    current_epoch = store |> Store.get_current_slot() |> Misc.compute_epoch_at_slot()
    block_epoch = Misc.compute_epoch_at_slot(block.slot)

    if current_epoch > block_epoch do
      # The block is from a prior epoch, the voting source will be pulled-up
      store.unrealized_justifications[block_root]
    else
      # The block is not from a prior epoch, therefore the voting source is not pulled up
      head_state = Store.get_state!(store, block_root)
      head_state.current_justified_checkpoint
    end
  end

  def is_previous_epoch_justified(%Store{} = store) do
    current_slot = Store.get_current_slot(store)
    current_epoch = Misc.compute_epoch_at_slot(current_slot)
    store.justified_checkpoint.epoch + 1 == current_epoch
  end

  @type block_tag() :: :genesis | :justified | :finalized | :head
  @type block_id() :: block_tag() | :invalid_id | Types.slot() | Types.root()
  @type block_info() ::
          {Types.root(), execution_optimistic? :: boolean(), finalized? :: boolean()}

  @spec root_by_id(block_id()) :: {:ok, block_info()} | {:error, String.t()} | :not_found
  def root_by_id(:head) do
    with {:ok, current_status} <- BeaconChain.get_current_status_message() do
      # TODO compute is_optimistic_or_invalid
      execution_optimistic = true
      {:ok, {current_status.head_root, execution_optimistic, false}}
    end
  end

  def root_by_id(:genesis), do: :not_found

  def root_by_id(:justified) do
    with {:ok, justified_checkpoint} <- ForkChoice.get_justified_checkpoint() do
      # TODO compute is_optimistic_or_invalid
      execution_optimistic = true
      {:ok, {justified_checkpoint.root, execution_optimistic, false}}
    end
  end

  def root_by_id(:finalized) do
    with {:ok, finalized_checkpoint} <- ForkChoice.get_finalized_checkpoint() do
      # TODO compute is_optimistic_or_invalid
      execution_optimistic = true
      {:ok, {finalized_checkpoint.root, execution_optimistic, true}}
    end
  end

  def root_by_id(:invalid_id), do: :invalid_id

  def root_by_id(hex_root) when is_binary(hex_root) do
    # TODO compute is_optimistic_or_invalid() and is_finalized()
    execution_optimistic = true
    finalized = false
    {:ok, {hex_root, execution_optimistic, finalized}}
  end

  def root_by_id(slot) when is_integer(slot) do
    with :ok <- check_valid_slot(slot, BeaconChain.get_current_slot()),
         {:ok, root} <- BlockStore.get_block_root_by_slot(slot) do
      # TODO compute is_optimistic_or_invalid() and is_finalized()
      execution_optimistic = true
      finalized = false
      {:ok, {root, execution_optimistic, finalized}}
    end
  end

  @spec get_state_root(Types.root()) :: {:ok, Types.root()} | {:error, String.t()} | :not_found
  def get_state_root(root) do
    with {:ok, signed_block} <- BlockStore.get_block(root) do
      {:ok, signed_block.message.state_root}
    end
  end

  defp check_valid_slot(slot, current_slot) when slot < current_slot, do: :ok

  defp check_valid_slot(slot, _current_slot),
    do: {:error, "slot #{slot} cannot be greater than current slot"}
end
