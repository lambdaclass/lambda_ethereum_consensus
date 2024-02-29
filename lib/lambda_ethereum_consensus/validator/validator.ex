defmodule LambdaEthereumConsensus.Validator do
  @moduledoc """
  GenServer that performs validator duties.
  """
  use GenServer

  require Logger
  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Validator.Utils

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def notify_new_slot(slot, head_root),
    do: GenServer.cast(__MODULE__, {:new_slot, slot, head_root})

  @impl true
  def init({slot, head_root}) do
    state = %{
      slot: slot,
      root: head_root,
      duties: {:not_computed, :not_computed},
      # TODO: get validator from config
      validator: 150_112
    }

    {:ok, state, {:continue, nil}}
  end

  @impl true
  def handle_continue(nil, %{slot: slot, root: root} = state) do
    epoch = Misc.compute_epoch_at_slot(slot)
    beacon = fetch_target_state(epoch, root)
    duties = maybe_update_duties(state.duties, beacon, epoch, state.validator)
    {:noreply, %{state | duties: duties}}
  end

  @impl true
  def handle_cast({:new_slot, slot, head_root}, %{validator: validator} = state) do
    new_state = update_state(state, slot, head_root)
    {index, committee_index, slot} = new_state.duties

    Logger.warning(
      "Updated duties. Validator #{validator} has to attest in committee #{committee_index} of slot #{slot} with index #{index}"
    )

    {:noreply, new_state}
  end

  defp update_state(%{slot: last_slot, root: last_root} = state, slot, head_root) do
    last_epoch = Misc.compute_epoch_at_slot(last_slot)
    epoch = Misc.compute_epoch_at_slot(slot)

    if last_epoch == epoch do
      state
    else
      target_root =
        if slot == Misc.compute_start_slot_at_epoch(epoch), do: head_root, else: last_root

      new_beacon = fetch_target_state(epoch, target_root)

      new_duties =
        shift_duties(state.duties, epoch, last_epoch)
        |> maybe_update_duties(new_beacon, epoch, state.validator)

      %{state | slot: slot, root: head_root, duties: new_duties}
    end
  end

  defp fetch_target_state(epoch, root) do
    {:ok, state} = Handlers.compute_target_checkpoint_state(epoch, root)
    state
  end

  defp shift_duties({_, ep1}, epoch, current_epoch) when epoch + 1 == current_epoch do
    {ep1, :not_computed}
  end

  defp shift_duties(_, _, _), do: {:not_computed, :not_computed}

  defp maybe_update_duties({:not_computed, _} = duties, beacon_state, epoch, validator) do
    compute_duty(duties, 0, beacon_state, epoch, validator)
    |> maybe_update_duties(beacon_state, epoch, validator)
  end

  defp maybe_update_duties({_, :not_computed} = duties, beacon_state, epoch, validator) do
    compute_duty(duties, 1, beacon_state, epoch, validator)
    |> maybe_update_duties(beacon_state, epoch, validator)
  end

  defp maybe_update_duties(duties, _, _, _), do: duties

  defp compute_duty(duties, index, beacon_state, epoch, validator) when index in 0..1 do
    # Can't fail
    {:ok, duty} = Utils.get_committee_assignment(beacon_state, epoch + index, validator)
    put_elem(duties, index, duty)
  end
end
