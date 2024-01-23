defmodule LambdaEthereumConsensus.ForkChoice.Handlers do
  @moduledoc """
  Handlers that update the fork choice store.
  """

  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.{Accessors, EpochProcessing, Misc, Predicates}

  alias Types.{
    Attestation,
    AttestationData,
    AttesterSlashing,
    Checkpoint,
    IndexedAttestation,
    SignedBeaconBlock,
    Store
  }

  import LambdaEthereumConsensus.Utils, only: [if_then_update: 3, map_ok: 2]

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

    base_state = Store.get_state(store, block.parent_root)

    cond do
      # Parent block must be known
      base_state |> is_nil() ->
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
        compute_post_state(store, signed_block, base_state)
    end
  end

  @doc """
  Run ``on_attestation`` upon receiving a new ``attestation`` from either within a block or directly on the wire.

  An ``attestation`` that is asserted as invalid may be valid at a later time,
  consider scheduling it for later processing in such case.
  """
  @spec on_attestation(Store.t(), Attestation.t(), boolean()) ::
          {:ok, Store.t()} | {:error, String.t()}
  def on_attestation(%Store{} = store, %Attestation{} = attestation, is_from_block) do
    with :ok <- check_attestation_valid(store, attestation, is_from_block),
         {:ok, store} <- store_target_checkpoint_state(store, attestation.data.target),
         # Get state at the `target` to fully validate attestation
         target_state = store.checkpoint_states[attestation.data.target],
         {:ok, indexed_attestation} <-
           Accessors.get_indexed_attestation(target_state, attestation),
         :ok <- check_valid_indexed_attestation(target_state, indexed_attestation) do
      # Update latest messages for attesting indices
      update_latest_messages(store, indexed_attestation.attesting_indices, attestation)
    else
      {:unknown_block, _} ->
        # TODO: this is just a patch, we should fetch blocks preemptively
        if is_from_block do
          {:ok, store}
        else
          {:error, "unknown block"}
        end

      v ->
        v
    end
  end

  defp check_valid_indexed_attestation(target_state, indexed_attestation) do
    if Predicates.is_valid_indexed_attestation(target_state, indexed_attestation),
      do: :ok,
      else: {:error, "invalid indexed attestation"}
  end

  @doc """
  Run ``on_attester_slashing`` immediately upon receiving a new ``AttesterSlashing``
  from either within a block or directly on the wire.
  """
  @spec on_attester_slashing(Store.t(), AttesterSlashing.t()) ::
          {:ok, Store.t()} | {:error, String.t()}
  def on_attester_slashing(
        %Store{} = store,
        %AttesterSlashing{
          attestation_1: %IndexedAttestation{} = attestation_1,
          attestation_2: %IndexedAttestation{} = attestation_2
        }
      ) do
    state = Store.get_state!(store, store.justified_checkpoint.root)

    cond do
      not Predicates.is_slashable_attestation_data(attestation_1.data, attestation_2.data) ->
        {:error, "attestation is not slashable"}

      not Predicates.is_valid_indexed_attestation(state, attestation_1) ->
        {:error, "attestation 1 is not valid"}

      not Predicates.is_valid_indexed_attestation(state, attestation_2) ->
        {:error, "attestation 2 is not valid"}

      true ->
        indices_1 = MapSet.new(attestation_1.attesting_indices)
        indices_2 = MapSet.new(attestation_2.attesting_indices)

        MapSet.intersection(indices_1, indices_2)
        |> MapSet.union(store.equivocating_indices)
        |> then(&{:ok, %Store{store | equivocating_indices: &1}})
    end
  end

  # Check the block is valid and compute the post-state.
  def compute_post_state(%Store{} = store, %SignedBeaconBlock{} = signed_block, state) do
    %{message: block} = signed_block
    block_root = Ssz.hash_tree_root!(block)

    with {:ok, state} <- StateTransition.state_transition(state, signed_block, true) do
      seconds_per_slot = ChainSpec.get("SECONDS_PER_SLOT")
      intervals_per_slot = Constants.intervals_per_slot()
      # Add proposer score boost if the block is timely
      time_into_slot = rem(store.time - store.genesis_time, seconds_per_slot)
      is_before_attesting_interval = time_into_slot < div(seconds_per_slot, intervals_per_slot)

      # Add new block and state to the store
      store
      |> Store.store_block(block_root, signed_block)
      |> Store.store_state(block_root, state)
      |> if_then_update(
        is_before_attesting_interval and Store.get_current_slot(store) == block.slot,
        &%Store{&1 | proposer_boost_root: block_root}
      )
      # Update checkpoints in store if necessary
      |> update_checkpoints(state.current_justified_checkpoint, state.finalized_checkpoint)
      # Eagerly compute unrealized justification and finality
      |> compute_pulled_up_tip(block_root)
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

  # Pull up the post-state of the block to the next epoch boundary
  def compute_pulled_up_tip(%Store{} = store, block_root) do
    result =
      Store.get_state!(store, block_root)
      |> EpochProcessing.process_justification_and_finalization()

    with {:ok, state} <- result do
      block = Store.get_block!(store, block_root)
      block_epoch = Misc.compute_epoch_at_slot(block.slot)
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
      |> then(&{:ok, &1})
    end
  end

  # Update unrealized checkpoints in store if necessary
  def update_unrealized_checkpoints(
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

  # Called ``validate_on_attestation`` in the spec.
  @spec check_attestation_valid(Store.t(), Attestation.t(), boolean()) ::
          :ok | {:error, String.t()} | {:unknown_block, Types.root()}
  defp check_attestation_valid(store, attestation, is_from_block)

  # If the given attestation is not from a beacon block message, we have to check the target epoch scope.
  defp check_attestation_valid(%Store{} = store, %Attestation{} = attestation, false) do
    with :ok <- target_epoch_against_current_time_valid?(store, attestation) do
      check_attestation_valid(store, attestation, true)
    end
  end

  defp check_attestation_valid(%Store{} = store, %Attestation{} = attestation, true) do
    target = attestation.data.target
    block_root = attestation.data.beacon_block_root
    head_block = Store.get_block(store, block_root)

    # NOTE: we use cond instead of an `and` chain for better formatting
    cond do
      # Check that the epoch number and slot number are matching
      target.epoch != Misc.compute_epoch_at_slot(attestation.data.slot) ->
        {:error, "mismatched epoch and slot"}

      # Attestation target must be for a known block.
      # If target block is unknown, delay consideration until block is found
      # TODO: delay consideration until block is found
      Store.get_block(store, target.root) |> is_nil() ->
        {:unknown_block, target.root}

      # Attestations must be for a known block. If block is unknown, delay consideration until the block is found
      # TODO: delay consideration until block is found
      is_nil(head_block) ->
        {:unknown_block, block_root}

      # Attestations must not be for blocks in the future. If not, the attestation should not be considered
      head_block.slot > attestation.data.slot ->
        {:error, "future head block"}

      # LMD vote must be consistent with FFG vote target
      target.root != Store.get_checkpoint_block(store, block_root, target.epoch) ->
        {:error, "mismatched head and target blocks"}

      # Attestations can only affect the fork choice of subsequent slots.
      # Delay consideration in the fork choice until their slot is in the past.
      # TODO: delay consideration
      Store.get_current_slot(store) <= attestation.data.slot ->
        {:error, "attestation is for a future slot"}

      true ->
        :ok
    end
  end

  # Called ``validate_target_epoch_against_current_time`` in the spec.
  defp target_epoch_against_current_time_valid?(%Store{} = store, %Attestation{} = attestation) do
    target = attestation.data.target

    # Attestations must be from the current or previous epoch
    current_epoch = store |> Store.get_current_slot() |> Misc.compute_epoch_at_slot()
    # Use GENESIS_EPOCH for previous when genesis to avoid underflow
    previous_epoch = max(current_epoch - 1, Constants.genesis_epoch())

    # If attestation target is from a future epoch, delay consideration until the epoch arrives
    # TODO: delay consideration until the epoch arrives
    if target.epoch in [current_epoch, previous_epoch], do: :ok, else: {:error, "future epoch"}
  end

  # Store target checkpoint state if not yet seen
  def store_target_checkpoint_state(%Store{} = store, %Checkpoint{} = target) do
    if Map.has_key?(store.checkpoint_states, target) do
      {:ok, store}
    else
      target_slot = Misc.compute_start_slot_at_epoch(target.epoch)

      Store.get_state!(store, target.root)
      |> then(
        &if(&1.slot < target_slot,
          do: StateTransition.process_slots(&1, target_slot),
          else: {:ok, &1}
        )
      )
      |> map_ok(
        &{:ok, %Store{store | checkpoint_states: Map.put(store.checkpoint_states, target, &1)}}
      )
    end
  end

  def prune_checkpoint_states(%Store{checkpoint_states: checkpoint_states} = store) do
    finalized_epoch = store.finalized_checkpoint.epoch

    checkpoint_states
    |> Map.reject(fn {%{epoch: epoch}, _} -> epoch < finalized_epoch end)
    |> then(&%{store | checkpoint_states: &1})
  end

  def update_latest_messages(%Store{} = store, attesting_indices, %Attestation{data: data}) do
    %AttestationData{target: target, beacon_block_root: beacon_block_root} = data
    messages = store.latest_messages
    message = %Checkpoint{epoch: target.epoch, root: beacon_block_root}

    attesting_indices
    |> Stream.reject(&MapSet.member?(store.equivocating_indices, &1))
    |> Stream.filter(&(not Map.has_key?(messages, &1) or target.epoch > messages[&1].epoch))
    |> Enum.reduce(messages, &Map.put(&2, &1, message))
    |> then(&{:ok, %Store{store | latest_messages: &1}})
  end
end
