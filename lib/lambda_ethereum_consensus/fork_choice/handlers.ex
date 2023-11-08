defmodule LambdaEthereumConsensus.ForkChoice.Handlers do
  @moduledoc """
  Handlers that update the fork choice store.
  """

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.{EpochProcessing, Misc}
  alias SszTypes.{Checkpoint, SignedBeaconBlock, Store}

  import LambdaEthereumConsensus.Utils, only: [if_then_update: 3]

  ### Public API ###

  @doc """
  Called once every tick (1 second). This function updates the Store's time.
  Also updates checkpoints and resets proposer boost at the beginning of every slot.
  """
  @spec on_tick(Store.t(), integer()) :: Store.t()
  def on_tick(%Store{} = store, time) do
    # If the ``store.time`` falls behind, while loop catches up slot by slot
    # to ensure that every previous slot is processed with ``on_tick_per_slot``
    seconds_per_slot = ChainSpec.get("SECONDS_PER_SLOT")
    tick_slot = div(time - store.genesis_time, seconds_per_slot)
    current_slot = Store.get_current_slot(store)
    next_slot_start = (current_slot + 1) * seconds_per_slot
    last_slot_start = tick_slot * seconds_per_slot

    :telemetry.execute([:sync, :store], %{slot: current_slot})

    next_slot_start..last_slot_start//seconds_per_slot
    |> Enum.reduce(store, &on_tick_per_slot(&2, &1))
    |> on_tick_per_slot(time)
  end

  @doc """
  Run ``on_block`` upon receiving a new block.

  A block that is asserted as invalid due to unavailable PoW block may be valid at a later time,
  consider scheduling it for later processing in such case.
  """
  @spec on_block(Store.t(), SignedBeaconBlock.t()) :: {:ok, Store.t()} | {:error, String.t()}
  def on_block(%Store{} = store, %SignedBeaconBlock{message: block} = signed_block) do
    finalized_slot =
      Misc.compute_start_slot_at_epoch(store.finalized_checkpoint.epoch)

    cond do
      # Parent block must be known
      not Map.has_key?(store.block_states, block.parent_root) ->
        {:error, "parent state not found in store"}

      # Blocks cannot be in the future. If they are, their
      # consideration must be delayed until they are in the past.
      Store.get_current_slot(store) < block.slot ->
        # TODO: handle this error somehow
        {:error, "block is from the future"}

      # Check that block is later than the finalized epoch slot (optimization to reduce calls to get_ancestor)
      block.slot <= finalized_slot ->
        {:error, "block is prior to last finalized epoch"}

      # Check block is a descendant of the finalized block at the checkpoint finalized slot
      store.finalized_checkpoint.root !=
          Store.get_checkpoint_block(
            store,
            block.parent_root,
            store.finalized_checkpoint.epoch
          ) ->
        {:error, "block isn't descendant of latest finalized block"}

      true ->
        compute_post_state(store, signed_block)
    end
  end

  # Check the block is valid and compute the post-state.
  defp compute_post_state(
         %Store{block_states: states} = store,
         %SignedBeaconBlock{message: block} = signed_block
       ) do
    state = states[block.parent_root]
    block_root = Ssz.hash_tree_root!(block)

    with {:ok, state} <- StateTransition.state_transition(state, signed_block, true) do
      # Add new block to the store
      blocks = Map.put(store.blocks, block_root, block)
      # Add new state for this block to the store
      states = Map.put(store.block_states, block_root, state)

      store = %Store{store | blocks: blocks, block_states: states}

      seconds_per_slot = ChainSpec.get("SECONDS_PER_SLOT")
      intervals_per_slot = ChainSpec.get("INTERVALS_PER_SLOT")
      # Add proposer score boost if the block is timely
      time_into_slot = rem(store.time - store.genesis_time, seconds_per_slot)
      is_before_attesting_interval = time_into_slot < div(seconds_per_slot, intervals_per_slot)

      store
      |> if_then_update(
        is_before_attesting_interval and Store.get_current_slot(store) == block.slot,
        &%Store{&1 | proposer_boost_root: block_root}
      )
      # Update checkpoints in store if necessary
      |> update_checkpoints(state.current_justified_checkpoint, state.finalized_checkpoint)
      # Eagerly compute unrealized justification and finality
      |> compute_pulled_up_tip(block_root)
      |> then(&{:ok, &1})
    end
  end

  ### Private functions ###

  # Update checkpoints in store if necessary
  defp update_checkpoints(store, justified_checkpoint, finalized_checkpoint) do
    store
    |> if_then_update(
      justified_checkpoint.epoch > store.justified_checkpoint.epoch,
      # Update justified checkpoint
      &%Store{&1 | justified_checkpoint: justified_checkpoint}
    )
    |> if_then_update(
      finalized_checkpoint.epoch > store.finalized_checkpoint.epoch,
      # Update finalized checkpoint
      &%Store{&1 | finalized_checkpoint: finalized_checkpoint}
    )
  end

  defp on_tick_per_slot(%Store{} = store, time) do
    previous_slot = Store.get_current_slot(store)

    # Update store time
    store = %Store{store | time: time}

    current_slot = Store.get_current_slot(store)

    store
    # If this is a new slot, reset store.proposer_boost_root
    |> if_then_update(current_slot > previous_slot, fn store ->
      %Store{store | proposer_boost_root: <<0::256>>}
      # If a new epoch, pull-up justification and finalization from previous epoch
      |> if_then_update(compute_slots_since_epoch_start(current_slot) == 0, fn store ->
        update_checkpoints(
          store,
          store.unrealized_justified_checkpoint,
          store.unrealized_finalized_checkpoint
        )
      end)
    end)
  end

  defp compute_pulled_up_tip(%Store{block_states: states} = store, block_root) do
    # Pull up the post-state of the block to the next epoch boundary
    # TODO: handle possible errors
    {:ok, state} = EpochProcessing.process_justification_and_finalization(states[block_root])

    block_epoch = Misc.compute_epoch_at_slot(store.blocks[block_root].slot)
    current_epoch = store |> Store.get_current_slot() |> Misc.compute_epoch_at_slot()

    unrealized_justifications =
      Map.put(store.unrealized_justifications, block_root, state.current_justified_checkpoint)

    %Store{store | unrealized_justifications: unrealized_justifications}
    |> update_unrealized_checkpoints(
      state.current_justified_checkpoint,
      state.finalized_checkpoint
    )
    |> if_then_update(
      block_epoch < current_epoch,
      # If the block is from a prior epoch, apply the realized values
      &update_checkpoints(&1, state.current_justified_checkpoint, state.finalized_checkpoint)
    )
  end

  # Update unrealized checkpoints in store if necessary
  defp update_unrealized_checkpoints(
         %Store{} = store,
         %Checkpoint{} = unrealized_justified_checkpoint,
         %Checkpoint{} = unrealized_finalized_checkpoint
       ) do
    store
    |> if_then_update(
      unrealized_justified_checkpoint.epoch > store.unrealized_justified_checkpoint.epoch,
      # Update unrealized justified checkpoint
      &%Store{&1 | unrealized_justified_checkpoint: unrealized_justified_checkpoint}
    )
    |> if_then_update(
      unrealized_finalized_checkpoint.epoch > store.unrealized_finalized_checkpoint.epoch,
      # Update unrealized finalized checkpoint
      &%Store{&1 | unrealized_finalized_checkpoint: unrealized_finalized_checkpoint}
    )
  end

  defp compute_slots_since_epoch_start(slot) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    slot - div(slot, slots_per_epoch) * slots_per_epoch
  end
end
