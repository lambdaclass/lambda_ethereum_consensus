defmodule LambdaEthereumConsensus.ForkChoice.Handlers do
  @moduledoc """
  Handlers that update the fork choice store.
  """

  alias SszTypes.Store

  ### Public API ###

  @doc """
  Called once every tick (1 second). This function updates the Store's time.
  Also updates checkpoints and resets proposer boost at the beginning of every slot.
  """
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
  Called whenever a signed block is received.
  """
  def on_block(store, _block) do
    {:ok, store}
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

  defp compute_slots_since_epoch_start(slot) do
    slots_per_epoch = ChainSpec.get("SLOTS_PER_EPOCH")
    slot - div(slot, slots_per_epoch) * slots_per_epoch
  end

  defp if_then_update(value, true, fun), do: fun.(value)
  defp if_then_update(value, false, _fun), do: value
end
