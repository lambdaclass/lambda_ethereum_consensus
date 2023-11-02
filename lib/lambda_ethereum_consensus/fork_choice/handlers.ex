defmodule LambdaEthereumConsensus.ForkChoice.Handlers do
  @moduledoc """
  Handlers that update the fork choice store.
  """

  alias SszTypes.Store

  ### Public API ###

  def on_tick(%Store{} = store, time) do
    seconds_per_slot = ChainSpec.get("SECONDS_PER_SLOT")
    tick_slot = div(time - store.genesis_time, seconds_per_slot)
    current_slot = Store.get_current_slot(store)

    current_slot..(tick_slot - 1)
    |> Enum.reduce_while(store, fn current_slot, store ->
      # TODO: simplify this by using time instead of slots
      previous_time = store.genesis_time + (current_slot + 1) * seconds_per_slot
      on_tick_per_slot(store, previous_time)
    end)
    |> on_tick_per_slot(time)
  end

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
