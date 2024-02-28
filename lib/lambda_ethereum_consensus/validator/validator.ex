defmodule LambdaEthereumConsensus.Validator do
  @moduledoc """
  GenServer that performs validator duties.
  """
  use GenServer

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.Validator.Utils

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def notify_new_slot(slot, head_root),
    do: GenServer.cast(__MODULE__, {:new_slot, slot, head_root})

  @impl true
  def init({slot, head_root}) do
    # pass initial beacon state
    {:ok,
     %{beacon: nil, last_root: nil, duties: {:not_computed, :not_computed}, validator: 150_112}}
  end

  @impl true
  def handle_cast({:new_slot, slot, head_root}, %{validator: validator} = state) do
    # compute new state
    current_epoch = Misc.compute_epoch_at_slot(slot)
    new_state = update_epoch_data(state, current_epoch, state.last_root)
    duties = update_duties(new_state.duties, new_state.beacon, new_state.epoch, validator)

    {:noreply, %{new_state | duties: duties}}
  end

  defp update_duties({:not_computed, _} = duties, beacon_state, epoch, validator) do
    compute_duty(duties, 0, beacon_state, epoch, validator)
    |> update_duties(beacon_state, epoch, validator)
  end

  defp update_duties({_, :not_computed} = duties, beacon_state, epoch, validator) do
    compute_duty(duties, 1, beacon_state, epoch, validator)
    |> update_duties(beacon_state, epoch, validator)
  end

  defp update_duties(duties, _, _, _), do: duties

  defp compute_duty(duties, index, beacon_state, epoch, validator) when index in 0..1 do
    # Can't fail
    {:ok, duty} = Utils.get_committee_assignment(beacon_state, epoch + index, validator)
    put_elem(duties, index, duty)
  end

  defp update_epoch_data(%{beacon: nil} = state, current_epoch, head_root) do
    %{state | beacon: Handlers.compute_target_checkpoint_state(current_epoch, head_root)}
  end

  defp update_epoch_data(%{beacon: beacon} = state, current_epoch, head_root) do
    epoch = Accessors.get_current_epoch(beacon)

    if current_epoch == epoch do
      state
    else
      new_beacon = Handlers.compute_target_checkpoint_state(current_epoch, head_root)
      %{state | beacon: new_beacon} |> shift_duties(epoch, current_epoch)
    end
  end

  defp shift_duties(%{duties: {_, ep1}} = state, epoch, current_epoch)
       when epoch + 1 == current_epoch do
    %{state | duties: {ep1, :not_computed}}
  end

  defp shift_duties(state, _, _), do: %{state | duties: {:not_computed, :not_computed}}
end
