defmodule LambdaEthereumConsensus.ForkChoice.Head do
  @moduledoc """
    Utility functions for the fork choice.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.Blocks
  alias Types.BeaconState
  alias Types.Store

  require Logger

  @spec get_head(Store.t()) :: {:ok, Types.root()} | {:error, any}
  def get_head(%Store{} = store) do
    # Get filtered block tree that only includes viable branches
    filtered_blocks = get_filtered_block_tree(store)
    # Execute the LMD-GHOST fork choice
    head = store.justified_checkpoint.root

    {_store, %BeaconState{} = justified_state} =
      Store.get_checkpoint_state(store, store.justified_checkpoint)

    start_time = System.monotonic_time(:millisecond)
    head = compute_head(store, filtered_blocks, head, justified_state)

    Logger.info(
      "Head computation took: #{(System.monotonic_time(:millisecond) - start_time) / 1000} s"
    )

    {:ok, head}
  end

  defp compute_head(store, blocks, current_root, justified_state) do
    children = for {parent_root, root} <- blocks, parent_root == current_root, do: root

    case children do
      [] ->
        current_root

      [only_child] ->
        # Directly continue without a max_by call
        compute_head(store, blocks, only_child, justified_state)

      candidates ->
        # Choose the candidate with the maximal weight according to get_weight/3
        start_time = System.monotonic_time(:millisecond)
        best_child = Enum.max_by(candidates, &get_weight(store, &1, justified_state))

        Logger.info(
          "Choosing best child took: #{(System.monotonic_time(:millisecond) - start_time) / 1000} s"
        )

        compute_head(store, blocks, best_child, justified_state)
    end
  end

  defp get_weight(%Store{} = store, root, state) do
    block = Blocks.get_block!(root)

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
  defp get_filtered_block_tree(%Store{} = store) do
    base = store.justified_checkpoint.root
    block = Blocks.get_block!(base)
    {_, blocks} = filter_block_tree(store, base, block, %{})
    blocks |> Enum.map(fn {root, block} -> {root, block.parent_root} end)
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
    current_epoch = Store.get_current_epoch(store)
    voting_source = get_voting_source(store, block_root)

    # The voting source should be at the same height as the store's justified checkpoint
    correct_justified =
      store.justified_checkpoint.epoch == Constants.genesis_epoch() or
        voting_source.epoch == store.justified_checkpoint.epoch or
        voting_source.epoch + 2 >= current_epoch

    # If the previous epoch is justified, the block should be pulled-up. In this case, check that unrealized
    # justification is higher than the store and that the voting source is not more than two epochs ago
    correct_justified =
      if not correct_justified and previous_epoch_justified?(store) do
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
  defp get_voting_source(%Store{} = store, block_root) do
    block = Blocks.get_block!(block_root)
    current_epoch = Store.get_current_epoch(store)
    block_epoch = Misc.compute_epoch_at_slot(block.slot)

    if current_epoch > block_epoch do
      # The block is from a prior epoch, the voting source will be pulled-up
      store.unrealized_justifications[block_root]
    else
      # The block is not from a prior epoch, therefore the voting source is not pulled up
      head_state = Store.get_state!(store, block_root).beacon_state
      head_state.current_justified_checkpoint
    end
  end

  defp previous_epoch_justified?(%Store{} = store) do
    current_epoch = Store.get_current_epoch(store)
    store.justified_checkpoint.epoch + 1 == current_epoch
  end
end
