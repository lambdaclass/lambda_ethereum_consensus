defmodule LambdaEthereumConsensus.Validator do
  @moduledoc """
  GenServer that performs validator duties.
  """
  use GenServer
  require Logger

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.P2P.Gossip
  alias LambdaEthereumConsensus.StateTransition.Accessors
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
    join_subnets_for_duties(duties, beacon, epoch)
    log_duties(duties, state.validator)
    {:noreply, %{state | duties: duties}}
  end

  @impl true
  def handle_cast({:new_slot, slot, head_root}, state) do
    # TODO: this doesn't take into account reorgs
    new_state = update_state(state, slot, head_root)
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

      move_subnets(state.duties, new_duties, new_beacon, epoch)
      log_duties(new_duties, state.validator)

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

  defp move_subnets({old_ep0, old_ep1}, {ep0, ep1}, beacon_state, epoch) do
    [old_subnet0, new_subnet0] =
      compute_subnet_ids_for_duties([old_ep0, ep0], beacon_state, epoch)

    [old_subnet1, new_subnet1] =
      compute_subnet_ids_for_duties([old_ep1, ep1], beacon_state, epoch + 1)

    old_subnets = MapSet.new([old_subnet0, old_subnet1])
    new_subnets = MapSet.new([new_subnet0, new_subnet1])

    # leave old subnets (except for recurring ones)
    MapSet.difference(old_subnets, new_subnets) |> leave()

    # join new subnets (except for recurring ones)
    MapSet.difference(new_subnets, old_subnets) |> join()
  end

  defp join_subnets_for_duties({ep0, ep1}, beacon_state, epoch) do
    [subnet0] = compute_subnet_ids_for_duties([ep0], beacon_state, epoch)
    [subnet1] = compute_subnet_ids_for_duties([ep1], beacon_state, epoch + 1)
    join([subnet0, subnet1])
  end

  defp compute_subnet_ids_for_duties(duties, beacon_state, epoch) do
    committees_per_slot = Accessors.get_committee_count_per_slot(beacon_state, epoch)
    Enum.map(duties, &compute_subnet_id_for_duty(&1, committees_per_slot))
  end

  defp compute_subnet_id_for_duty({_, committee_index, slot}, committees_per_slot) do
    Utils.compute_subnet_for_attestation(committees_per_slot, slot, committee_index)
  end

  defp join(subnets) do
    if not Enum.empty?(subnets) do
      Logger.info("Joining subnets: #{Enum.join(subnets, ", ")}")
      Enum.each(subnets, &Gossip.Attestation.join/1)
    end
  end

  defp leave(subnets) do
    if not Enum.empty?(subnets) do
      Logger.info("Leaving subnets: #{Enum.join(subnets, ", ")}")
      Enum.each(subnets, &Gossip.Attestation.leave/1)
    end
  end

  defp log_duties({{i0, ci0, slot0}, {i1, ci1, slot1}}, validator) do
    Logger.info(
      "Validator #{validator} has to attest in committee #{ci0} of slot #{slot0} with index #{i0}," <>
        " and in committee #{ci1} of slot #{slot1} with index #{i1}"
    )
  end
end
