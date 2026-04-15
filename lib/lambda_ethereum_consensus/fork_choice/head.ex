defmodule LambdaEthereumConsensus.ForkChoice.Head do
  @moduledoc """
    Utility functions for the fork choice.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BeaconState
  alias Types.Store

  @spec get_head(Store.t()) :: {:ok, Types.root()} | {:error, any}
  def get_head(%Store{} = store) do
    # Get filtered block tree that only includes viable branches
    filtered_blocks = get_filtered_block_tree(store)
    # Execute the LMD-GHOST fork choice
    head = store.justified_checkpoint.root

    # Cache-only checkpoint state lookup to avoid Libp2pPort stalling on
    # eleveldb.get/3 (10+ min NIF blocks). If justified state isn't cached,
    # fall back to returning the justified checkpoint root as head without
    # running LMD-GHOST weight computation. This is conservative and safe —
    # next block will re-attempt with a warm cache.
    case Store.get_checkpoint_state_cached(store, store.justified_checkpoint) do
      {_store, %BeaconState{} = justified_state} ->
        head = compute_head(store, filtered_blocks, head, justified_state)
        {:ok, head}

      {_store, nil} ->
        {:ok, store.head_root || store.justified_checkpoint.root}
    end
  end

  defp compute_head(store, blocks, current_root, justified_state) do
    children = for {root, parent_root} <- blocks, parent_root == current_root, do: root

    case children do
      [] ->
        current_root

      [only_child] ->
        # Directly continue without a max_by call
        compute_head(store, blocks, only_child, justified_state)

      candidates ->
        # Choose the candidate with the maximal weight according to get_weight/3
        best_child =
          candidates
          # Ties broken by favoring block with lexicographically higher root
          |> Enum.sort(:desc)
          |> Enum.max_by(&get_weight(store, &1, justified_state))

        compute_head(store, blocks, best_child, justified_state)
    end
  end

  defp get_weight(%Store{} = store, root, state) do
    # Cache-only — avoid blocking Libp2pPort on LevelDB reads.
    block = Blocks.get_block_cached(root)

    # If block isn't cached, return 0 weight (conservative — favors cached branches).
    if is_nil(block) do
      0
    else
      get_weight_for_block(store, root, block, state)
    end
  end

  defp get_weight_for_block(store, root, block, state) do
    # PERF: use ``Aja.Vector.foldl``
    {attestation_score, _} =
      Accessors.get_active_validator_indices(state, Accessors.get_current_epoch(state))
      |> Stream.reject(&Aja.Vector.at!(state.validators, &1).slashed)
      |> Stream.filter(&Map.has_key?(store.latest_messages, &1))
      |> Stream.reject(&MapSet.member?(store.equivocating_indices, &1))
      |> Enum.reduce({0, %{}}, fn i, {acc, ancestors} ->
        vote_root = store.latest_messages[i].root

        ancestors =
          Map.put_new_lazy(ancestors, vote_root, fn ->
            Store.get_ancestor(store, vote_root, block.slot)
          end)

        delta =
          if Map.fetch!(ancestors, vote_root) == root do
            Aja.Vector.at!(state.validators, i).effective_balance
          else
            0
          end

        {acc + delta, ancestors}
      end)

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
  # Only return the roots and their parent roots.
  defp get_filtered_block_tree(%Store{} = store) do
    base = store.justified_checkpoint.root
    # Cache-only — justified root should almost always be cached.
    block = Blocks.get_block_cached(base)

    if is_nil(block) do
      # Return empty tree — head defaults to justified root.
      []
    else
      {_, blocks} = filter_block_tree(store, base, block, %{})
      Enum.map(blocks, fn {root, block} -> {root, block.parent_root} end)
    end
  end

  defp filter_block_tree(%Store{} = store, block_root, block, blocks) do
    children = Store.get_children(store, block_root)

    # If any children branches contain expected finalized/justified checkpoints,
    # add to filtered block-tree and signal viability to parent.
    {filter_block_tree_result, new_blocks} =
      Enum.map_reduce(children, blocks, fn {root, block}, acc ->
        filter_block_tree(store, root, block, acc)
      end)

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
    correct_justified = justified_check(store, block_root)
    correct_finalized = finalized_check(store, block_root)

    # If expected finalized/justified, add to viable block-tree and signal viability to parent.
    if correct_justified and correct_finalized do
      {true, Map.put(blocks, block_root, block)}
    else
      {false, blocks}
    end
  end

  defp justified_check(%Store{} = store, block_root) do
    current_epoch = Store.get_current_epoch(store)
    voting_source = get_voting_source(store, block_root)

    correct =
      store.justified_checkpoint.epoch == Constants.genesis_epoch() or
        voting_source.epoch == store.justified_checkpoint.epoch or
        voting_source.epoch + 2 >= current_epoch

    if not correct and previous_epoch_justified?(store) do
      pulled_up_check(store, block_root, voting_source, current_epoch)
    else
      correct
    end
  end

  defp pulled_up_check(store, block_root, voting_source, current_epoch) do
    unrealized = store.unrealized_justifications[block_root]

    unrealized != nil and
      unrealized.epoch >= store.justified_checkpoint.epoch and
      voting_source.epoch + 2 >= current_epoch
  end

  defp finalized_check(%Store{} = store, block_root) do
    store.finalized_checkpoint.epoch == Constants.genesis_epoch() or
      store.finalized_checkpoint.root ==
        Store.get_checkpoint_block(store, block_root, store.finalized_checkpoint.epoch)
  end

  # Compute the voting source checkpoint in event that block with root ``block_root`` is the head block
  defp get_voting_source(%Store{} = store, block_root) do
    # Cache-only — avoid blocking Libp2pPort on LevelDB reads.
    case Blocks.get_block_cached(block_root) do
      nil ->
        # Block not cached — fall back to justified checkpoint.
        store.justified_checkpoint

      block ->
        get_voting_source_for_block(store, block_root, block)
    end
  end

  defp get_voting_source_for_block(store, block_root, block) do
    current_epoch = Store.get_current_epoch(store)
    block_epoch = Misc.compute_epoch_at_slot(block.slot)

    if current_epoch > block_epoch do
      # The block is from a prior epoch, the voting source will be pulled-up.
      # After restart/recovery, unrealized_justifications may not have this root
      # (rebuild_tree doesn't populate it). Fall back to the block's state.
      store.unrealized_justifications[block_root] ||
        voting_source_fallback(store, block_root)
    else
      # The block is not from a prior epoch, therefore the voting source is not pulled up.
      # Use cache-only lookup to avoid Libp2pPort stalling on LevelDB reads.
      # On cache miss, fall back to voting_source_fallback which also uses cached
      # lookups and returns store.justified_checkpoint if no state is available.
      case Store.get_state_cached(store, block_root) do
        %{beacon_state: state} -> state.current_justified_checkpoint
        nil -> voting_source_fallback(store, block_root)
      end
    end
  end

  defp voting_source_fallback(store, block_root) do
    case Store.get_state_cached(store, block_root) do
      %{beacon_state: state} -> state.current_justified_checkpoint
      nil -> store.justified_checkpoint
    end
  end

  defp previous_epoch_justified?(%Store{} = store) do
    current_epoch = Store.get_current_epoch(store)
    store.justified_checkpoint.epoch + 1 == current_epoch
  end
end
