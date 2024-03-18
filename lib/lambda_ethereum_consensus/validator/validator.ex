defmodule LambdaEthereumConsensus.Validator do
  @moduledoc """
  GenServer that performs validator duties.
  """
  use GenServer
  require Logger

  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.P2P.Gossip
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Validator.Utils
  alias Types.Attestation

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def notify_new_block(slot, head_root),
    do: GenServer.cast(__MODULE__, {:new_block, slot, head_root})

  @impl true
  def init({slot, head_root}) do
    state = %{
      slot: slot,
      root: head_root,
      duties: %{
        attester: {:not_computed, :not_computed}
      },
      # TODO: get validator from config
      validator: %{index: 55, privkey: <<652_916_760::256>>}
    }

    {:ok, state, {:continue, nil}}
  end

  @impl true
  def handle_continue(nil, %{slot: slot, root: root} = state) do
    epoch = Misc.compute_epoch_at_slot(slot)
    beacon = fetch_target_state(epoch, root)
    duties = maybe_update_duties(state.duties, beacon, epoch, state.validator)
    join_subnets_for_duties(duties)
    log_duties(duties, state.validator.index)
    {:noreply, %{state | duties: duties}}
  end

  @impl true
  def handle_cast({:new_block, slot, head_root}, state) do
    # TODO: this doesn't take into account reorgs or empty slots
    new_state = update_state(state, slot, head_root)

    if should_attest?(state, slot), do: attest(state)
    maybe_publish_aggregate(state, slot)

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

      move_subnets(state.duties, new_duties)
      log_duties(new_duties, state.validator.index)

      %{state | slot: slot, root: head_root, duties: new_duties}
    end
  end

  defp fetch_target_state(epoch, root) do
    {:ok, state} = Handlers.compute_target_checkpoint_state(epoch, root)
    state
  end

  defp shift_duties(%{attester: {_, ep1}} = duties, epoch, current_epoch)
       when epoch + 1 == current_epoch do
    %{duties | attester: {ep1, :not_computed}}
  end

  defp shift_duties(duties, _, _), do: %{duties | attester: {:not_computed, :not_computed}}

  defp maybe_update_duties(duties, beacon_state, epoch, validator) do
    attester_duties =
      maybe_update_attester_duties(duties.attester, beacon_state, epoch, validator)

    %{duties | attester: attester_duties}
  end

  defp maybe_update_attester_duties({:not_computed, _} = duties, beacon_state, epoch, validator) do
    compute_attester_duty(duties, 0, beacon_state, epoch, validator)
    |> maybe_update_attester_duties(beacon_state, epoch, validator)
  end

  defp maybe_update_attester_duties({_, :not_computed} = duties, beacon_state, epoch, validator) do
    compute_attester_duty(duties, 1, beacon_state, epoch, validator)
    |> maybe_update_attester_duties(beacon_state, epoch, validator)
  end

  defp maybe_update_attester_duties(duties, _, _, _), do: duties

  defp compute_attester_duty(duties, index, beacon_state, base_epoch, validator)
       when index in 0..1 do
    epoch = base_epoch + index
    # Can't fail
    {:ok, duty} = Utils.get_committee_assignment(beacon_state, epoch, validator.index)

    duty =
      update_with_aggregation_duty(duty, beacon_state, validator.privkey)
      |> update_with_subnet_id(beacon_state, epoch)

    put_elem(duties, index, duty)
  end

  defp move_subnets(%{attester: {old_ep0, old_ep1}}, %{attester: {ep0, ep1}}) do
    old_subnets = MapSet.new([old_ep0.subnet_id, old_ep1.subnet_id])
    new_subnets = MapSet.new([ep0.subnet_id, ep1.subnet_id])

    # leave old subnets (except for recurring ones)
    MapSet.difference(old_subnets, new_subnets) |> leave()

    # join new subnets (except for recurring ones)
    MapSet.difference(new_subnets, old_subnets) |> join()
  end

  defp join_subnets_for_duties(%{attester: {ep0, ep1}}) do
    join([ep0.subnet_id, ep1.subnet_id])
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

  defp log_duties(%{attester: attester_duties}, validator_index) do
    {%{index_in_committee: i0, committee_index: ci0, slot: slot0},
     %{index_in_committee: i1, committee_index: ci1, slot: slot1}} = attester_duties

    Logger.info(
      "Validator #{validator_index} has to attest in committee #{ci0} of slot #{slot0} with index #{i0}," <>
        " and in committee #{ci1} of slot #{slot1} with index #{i1}"
    )
  end

  defp should_attest?(%{duties: %{attester: {%{slot: duty_slot}, _}}}, slot),
    do: duty_slot == slot

  defp attest(state) do
    {current_duty, _} = state.duties.attester

    {subnet_id, attestation} =
      produce_attestation(current_duty, state.root, state.validator.privkey)

    Logger.info("[Validator] Attesting in slot #{attestation.data.slot} on subnet #{subnet_id}")
    Gossip.Attestation.publish(subnet_id, attestation)

    if current_duty.is_aggregator do
      Logger.info("[Validator] Collecting messages for future aggregation...")
      Gossip.Attestation.collect(subnet_id, attestation)
    end
  end

  def maybe_publish_aggregate(
        %{duties: %{attester: {%{slot: duty_slot, is_aggregator: true} = duty, _}}},
        slot
      )
      when duty_slot == slot + 1 do
    # TODO: generate aggregate and publish
    _ = Gossip.Attestation.stop_collecting(duty.subnet_id)
  end

  def maybe_publish_aggregate(_, _), do: :ok

  defp produce_attestation(duty, head_root, privkey) do
    %{
      index_in_committee: index_in_committee,
      committee_length: committee_length,
      committee_index: committee_index,
      slot: slot
    } = duty

    head_state = BlockStates.get_state!(head_root) |> process_slots(slot)
    head_epoch = Misc.compute_epoch_at_slot(slot)

    epoch_boundary_block_root =
      if Misc.compute_start_slot_at_epoch(head_epoch) == slot do
        head_root
      else
        # Can't fail as long as slot isn't ancient for attestation purposes
        {:ok, root} = Accessors.get_block_root(head_state, head_epoch)
        root
      end

    attestation_data = %Types.AttestationData{
      slot: slot,
      index: committee_index,
      beacon_block_root: head_root,
      source: head_state.current_justified_checkpoint,
      target: %Types.Checkpoint{
        epoch: head_epoch,
        root: epoch_boundary_block_root
      }
    }

    bits = BitList.default(committee_length) |> BitList.set(index_in_committee)

    signature = Utils.get_attestation_signature(head_state, attestation_data, privkey)

    attestation = %Attestation{
      data: attestation_data,
      aggregation_bits: bits,
      signature: signature
    }

    {duty.subnet_id, attestation}
  end

  defp process_slots(%{slot: old_slot} = state, slot) when old_slot == slot, do: state

  defp process_slots(state, slot) do
    {:ok, st} = StateTransition.process_slots(state, slot)
    st
  end

  defp update_with_aggregation_duty(duty, beacon_state, privkey) do
    Utils.get_slot_signature(beacon_state, duty.slot, privkey)
    |> Utils.aggregator?(duty.committee_length)
    |> then(&Map.put(duty, :is_aggregator, &1))
  end

  defp update_with_subnet_id(duty, beacon_state, epoch) do
    committees_per_slot = Accessors.get_committee_count_per_slot(beacon_state, epoch)

    subnet_id =
      Utils.compute_subnet_for_attestation(committees_per_slot, duty.slot, duty.committee_index)

    Map.put(duty, :subnet_id, subnet_id)
  end
end
