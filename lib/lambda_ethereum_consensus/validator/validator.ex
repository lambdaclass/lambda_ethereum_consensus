defmodule LambdaEthereumConsensus.Validator do
  @moduledoc """
  GenServer that performs validator duties.
  """
  use GenServer
  require Logger

  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.Beacon.PendingBlocks
  alias LambdaEthereumConsensus.ForkChoice.Handlers
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Utils
  alias LambdaEthereumConsensus.Utils.BitField
  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Validator.BlockBuilder
  alias LambdaEthereumConsensus.Validator.BuildBlockRequest
  alias Types.Attestation

  @default_graffiti_message "Lambda, so gentle, so good"

  ##########################
  ### Public API
  ##########################

  def start_link({_, _, {pubkey, _}} = opts) do
    # TODO: if possible, use validator index instead of pubkey?
    name = Atom.to_string(__MODULE__) <> Utils.format_shorten_binary(pubkey)
    GenServer.start_link(__MODULE__, opts, name: String.to_atom(name))
  end

  def notify_new_block(slot, head_root),
    do: GenServer.cast(__MODULE__, {:new_block, slot, head_root})

  ##########################
  ### GenServer Callbacks
  ##########################

  @type state :: %{
          slot: Types.slot(),
          root: Types.root(),
          duties: %{
            attester: list(:not_computed),
            proposer: :not_computed | list(Types.slot())
          },
          validator: any(),
          payload_builder: {Types.slot(), Types.root(), BlockBuilder.payload_id()} | nil
        }

  @impl true
  @spec init({Types.slot(), Types.root(), {Bls.pubkey(), Bls.privkey()}}) ::
          {:ok, state, {:continue, any}}
  def init({head_slot, head_root, {pubkey, privkey}}) do
    state = %{
      slot: head_slot,
      root: head_root,
      duties: empty_duties(),
      validator: %{
        pubkey: pubkey,
        privkey: privkey,
        index: nil
      },
      payload_builder: nil
    }

    {:ok, state, {:continue, nil}}
  end

  @spec handle_continue(nil, state) :: {:noreply, state}

  @impl true
  def handle_continue(nil, %{slot: slot, root: root} = state) do
    case try_setup_validator(state, slot, root) do
      nil ->
        Logger.error("[Validator] Public key not found in the validator set")
        {:noreply, state}

      new_state ->
        {:noreply, new_state}
    end
  end

  @spec try_setup_validator(state, Types.slot(), Types.root()) :: state | nil
  defp try_setup_validator(state, slot, root) do
    epoch = Misc.compute_epoch_at_slot(slot)
    beacon = fetch_target_state(epoch, root)

    case fetch_validator_index(beacon, state.validator) do
      nil ->
        nil

      validator_index ->
        Logger.info("[Validator] Setup for validator number #{validator_index} complete")
        validator = %{state.validator | index: validator_index}
        duties = maybe_update_duties(state.duties, beacon, epoch, validator)
        join_subnets_for_duties(duties)
        log_duties(duties, validator_index)
        %{state | duties: duties, validator: validator}
    end
  end

  @spec handle_cast(any, state) :: {:noreply, state}

  @impl true
  def handle_cast(_, %{validator: nil} = state), do: {:noreply, state}

  # If we couldn't find the validator before, we just try again
  def handle_cast({:new_block, slot, head_root} = msg, %{validator: %{index: nil}} = state) do
    case try_setup_validator(state, slot, head_root) do
      nil -> {:noreply, state}
      new_state -> handle_cast(msg, new_state)
    end
  end

  def handle_cast({:new_block, slot, head_root}, state),
    do: {:noreply, handle_new_block(slot, head_root, state)}

  def handle_cast({:on_tick, _}, %{validator: %{index: nil}} = state), do: {:noreply, state}

  def handle_cast({:on_tick, logical_time}, state),
    do: {:noreply, handle_tick(logical_time, state)}

  ##########################
  ### Private Functions
  ##########################

  defp empty_duties() do
    %{
      # Order is: previous epoch, current epoch, next epoch
      attester: [:not_computed, :not_computed, :not_computed],
      proposer: :not_computed
    }
  end

  defp handle_new_block(slot, head_root, state) do
    # TODO: this doesn't take into account reorgs
    state
    |> update_state(slot, head_root)
    |> maybe_attest(slot)
    |> maybe_build_payload(slot + 1)
  end

  defp handle_tick({slot, :first_third}, state) do
    # Here we may:
    # 1. propose our blocks
    # 2. (TODO) start collecting attestations for aggregation
    maybe_propose(state, slot)
    |> update_state(slot, state.root)
  end

  defp handle_tick({slot, :second_third}, state) do
    # Here we may:
    # 1. send our attestation for an empty slot
    # 2. start building a payload
    state
    |> maybe_attest(slot)
    |> maybe_build_payload(slot + 1)
  end

  defp handle_tick({slot, :last_third}, state) do
    # Here we may publish our attestation aggregate
    maybe_publish_aggregate(state, slot)
  end

  defp update_state(%{slot: slot, root: root} = state, slot, root), do: state

  defp update_state(%{slot: slot, root: _other_root} = state, slot, head_root) do
    # TODO: this log is appearing for every block
    # Logger.warning("[Validator] Block came late", slot: slot, root: head_root)

    # TODO: rollback stale data instead of the whole cache
    epoch = Misc.compute_epoch_at_slot(slot + 1)
    recompute_duties(state, 0, epoch, slot, head_root)
  end

  defp update_state(%{slot: last_slot} = state, slot, head_root) do
    last_epoch = Misc.compute_epoch_at_slot(last_slot + 1)
    epoch = Misc.compute_epoch_at_slot(slot + 1)

    if last_epoch == epoch do
      %{state | slot: slot, root: head_root}
    else
      recompute_duties(state, last_epoch, epoch, slot, head_root)
    end
  end

  defp recompute_duties(%{root: last_root} = state, last_epoch, epoch, slot, head_root) do
    start_slot = Misc.compute_start_slot_at_epoch(epoch)
    target_root = if slot == start_slot, do: head_root, else: last_root

    # Process the start of the new epoch
    new_beacon = fetch_target_state(epoch, target_root) |> go_to_slot(start_slot)

    new_duties =
      shift_duties(state.duties, epoch, last_epoch)
      |> maybe_update_duties(new_beacon, epoch, state.validator)

    move_subnets(state.duties, new_duties)
    log_duties(new_duties, state.validator.index)

    %{state | slot: slot, root: head_root, duties: new_duties}
  end

  @spec fetch_target_state(Types.epoch(), Types.root()) :: Types.BeaconState.t()
  defp fetch_target_state(epoch, root) do
    {:ok, state} = Handlers.compute_target_checkpoint_state(epoch, root)
    state
  end

  defp shift_duties(%{attester: [_ep0, ep1, ep2]} = duties, epoch, current_epoch) do
    case current_epoch - epoch do
      1 -> %{duties | attester: [ep1, ep2, :not_computed]}
      2 -> %{duties | attester: [ep2, :not_computed, :not_computed]}
      _ -> %{duties | attester: [:not_computed, :not_computed, :not_computed]}
    end
  end

  defp maybe_update_duties(duties, beacon_state, epoch, validator) do
    attester_duties =
      maybe_update_attester_duties(duties.attester, beacon_state, epoch, validator)

    proposer_duties = compute_proposer_duties(beacon_state, epoch, validator.index)
    # To avoid edge-cases
    old_duty =
      case duties.proposer do
        :not_computed -> []
        old -> old |> Enum.reverse() |> Enum.take(1)
      end

    %{duties | attester: attester_duties, proposer: Enum.dedup(old_duty ++ proposer_duties)}
  end

  defp maybe_update_attester_duties([epp, ep0, ep1], beacon_state, epoch, validator) do
    duties =
      Stream.with_index([ep0, ep1])
      |> Enum.map(fn
        {:not_computed, i} -> compute_attester_duty(beacon_state, epoch + i, validator)
        {d, _} -> d
      end)

    [epp | duties]
  end

  defp compute_attester_duty(beacon_state, epoch, validator) do
    # Can't fail
    {:ok, duty} = Utils.get_committee_assignment(beacon_state, epoch, validator.index)

    case duty do
      nil ->
        nil

      duty ->
        duty
        |> Map.put(:attested?, false)
        |> update_with_aggregation_duty(beacon_state, validator.privkey)
        |> update_with_subnet_id(beacon_state, epoch)
    end
  end

  defp get_subnet_ids(duties),
    do: duties |> Stream.reject(&(&1 == :not_computed)) |> Enum.map(& &1.subnet_id)

  defp move_subnets(%{attester: old_duties}, %{attester: new_duties}) do
    old_subnets = old_duties |> get_subnet_ids() |> MapSet.new()
    new_subnets = new_duties |> get_subnet_ids() |> MapSet.new()

    # leave old subnets (except for recurring ones)
    MapSet.difference(old_subnets, new_subnets) |> leave()

    # join new subnets (except for recurring ones)
    MapSet.difference(new_subnets, old_subnets) |> join()
  end

  defp join_subnets_for_duties(%{attester: duties}) do
    duties |> get_subnet_ids() |> join()
  end

  defp join(subnets) do
    if not Enum.empty?(subnets) do
      Logger.debug("Joining subnets: #{Enum.join(subnets, ", ")}")
      Enum.each(subnets, &Gossip.Attestation.join/1)
    end
  end

  defp leave(subnets) do
    if not Enum.empty?(subnets) do
      Logger.debug("Leaving subnets: #{Enum.join(subnets, ", ")}")
      Enum.each(subnets, &Gossip.Attestation.leave/1)
    end
  end

  defp log_duties(%{attester: attester_duties, proposer: proposer_duties}, validator_index) do
    attester_duties
    # Drop the first element, which is the previous epoch's duty
    |> Stream.drop(1)
    |> Enum.each(fn %{index_in_committee: i, committee_index: ci, slot: slot} ->
      Logger.debug(
        "[Validator] #{validator_index} has to attest in committee #{ci} of slot #{slot} with index #{i}"
      )
    end)

    Enum.each(proposer_duties, fn slot ->
      Logger.info("[Validator] #{validator_index} has to propose a block in slot #{slot}!")
    end)
  end

  defp get_current_attester_duty(%{duties: %{attester: attester_duties}}, current_slot) do
    Enum.find(attester_duties, fn
      :not_computed -> false
      duty -> duty.slot == current_slot
    end)
  end

  defp replace_attester_duty(state, duty, new_duty) do
    attester_duties =
      Enum.map(state.duties.attester, fn
        ^duty -> new_duty
        d -> d
      end)

    %{state | duties: %{state.duties | attester: attester_duties}}
  end

  defp maybe_attest(state, slot) do
    case get_current_attester_duty(state, slot) do
      %{attested?: false} = duty ->
        attest(state, duty)
        replace_attester_duty(state, duty, %{duty | attested?: true})

      _ ->
        state
    end
  end

  defp attest(state, current_duty) do
    subnet_id = current_duty.subnet_id
    attestation = produce_attestation(current_duty, state.root, state.validator.privkey)

    Logger.info("[Validator] Attesting in slot #{attestation.data.slot} on subnet #{subnet_id}")
    Gossip.Attestation.publish(subnet_id, attestation)

    if current_duty.should_aggregate? do
      Logger.info("[Validator] Collecting messages for future aggregation...")
      Gossip.Attestation.collect(subnet_id, attestation)
    end
  end

  # We publish our aggregate on the next slot, and when we're an aggregator
  defp maybe_publish_aggregate(%{validator: validator} = state, slot) do
    case get_current_attester_duty(state, slot) do
      %{should_aggregate?: true} = duty ->
        publish_aggregate(duty, validator)
        replace_attester_duty(state, duty, %{duty | should_aggregate?: false})

      _ ->
        state
    end
  end

  defp publish_aggregate(duty, validator) do
    case Gossip.Attestation.stop_collecting(duty.subnet_id) do
      {:ok, attestations} ->
        Logger.info("[Validator] Publishing aggregate of slot #{duty.slot}")

        aggregate_attestations(attestations)
        |> append_proof(duty.selection_proof, validator)
        |> append_signature(duty.signing_domain, validator)
        |> Gossip.Attestation.publish_aggregate()

      _ ->
        :ok
    end
  end

  defp aggregate_attestations(attestations) do
    aggregation_bits =
      attestations
      |> Stream.map(&Map.fetch!(&1, :aggregation_bits))
      |> Enum.reduce(&BitField.bitwise_or/2)

    {:ok, signature} = attestations |> Enum.map(&Map.fetch!(&1, :signature)) |> Bls.aggregate()

    %{List.first(attestations) | aggregation_bits: aggregation_bits, signature: signature}
  end

  defp append_proof(aggregate, proof, validator) do
    %Types.AggregateAndProof{
      aggregator_index: validator.index,
      aggregate: aggregate,
      selection_proof: proof
    }
  end

  defp append_signature(aggregate_and_proof, signing_domain, %{privkey: privkey}) do
    signing_root = Misc.compute_signing_root(aggregate_and_proof, signing_domain)
    {:ok, signature} = Bls.sign(privkey, signing_root)
    %Types.SignedAggregateAndProof{message: aggregate_and_proof, signature: signature}
  end

  defp produce_attestation(duty, head_root, privkey) do
    %{
      index_in_committee: index_in_committee,
      committee_length: committee_length,
      committee_index: committee_index,
      slot: slot
    } = duty

    head_state = BlockStates.get_state!(head_root) |> go_to_slot(slot)
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

    bits = BitList.zero(committee_length) |> BitList.set(index_in_committee)

    signature = Utils.get_attestation_signature(head_state, attestation_data, privkey)

    %Attestation{
      data: attestation_data,
      aggregation_bits: bits,
      signature: signature
    }
  end

  defp go_to_slot(%{slot: old_slot} = state, slot) when old_slot == slot, do: state

  defp go_to_slot(%{slot: old_slot} = state, slot) when old_slot < slot do
    {:ok, st} = StateTransition.process_slots(state, slot)
    st
  end

  defp go_to_slot(%{latest_block_header: %{parent_root: parent_root}}, slot) do
    BlockStates.get_state!(parent_root) |> go_to_slot(slot)
  end

  defp update_with_aggregation_duty(duty, beacon_state, privkey) do
    proof = Utils.get_slot_signature(beacon_state, duty.slot, privkey)

    if Utils.aggregator?(proof, duty.committee_length) do
      epoch = Misc.compute_epoch_at_slot(duty.slot)
      domain = Accessors.get_domain(beacon_state, Constants.domain_aggregate_and_proof(), epoch)

      Map.put(duty, :should_aggregate?, true)
      |> Map.put(:selection_proof, proof)
      |> Map.put(:signing_domain, domain)
    else
      Map.put(duty, :should_aggregate?, false)
    end
  end

  defp update_with_subnet_id(duty, beacon_state, epoch) do
    committees_per_slot = Accessors.get_committee_count_per_slot(beacon_state, epoch)

    subnet_id =
      Utils.compute_subnet_for_attestation(committees_per_slot, duty.slot, duty.committee_index)

    Map.put(duty, :subnet_id, subnet_id)
  end

  @spec fetch_validator_index(Types.BeaconState.t(), %{index: nil, pubkey: Bls.pubkey()}) ::
          non_neg_integer() | nil
  defp fetch_validator_index(beacon, %{index: nil, pubkey: pk}) do
    Enum.find_index(beacon.validators, &(&1.pubkey == pk))
  end

  defp compute_proposer_duties(beacon_state, epoch, validator_index) do
    start_slot = Misc.compute_start_slot_at_epoch(epoch)

    start_slot..(start_slot + ChainSpec.get("SLOTS_PER_EPOCH") - 1)
    |> Enum.flat_map(fn slot ->
      # Can't fail
      {:ok, proposer_index} = Accessors.get_beacon_proposer_index(beacon_state, slot)
      if proposer_index == validator_index, do: [slot], else: []
    end)
  end

  defp proposer?(%{duties: %{proposer: slots}}, slot), do: Enum.member?(slots, slot)

  defp maybe_build_payload(%{root: head_root} = state, proposed_slot) do
    if proposer?(state, proposed_slot) do
      start_payload_builder(state, proposed_slot, head_root)
    else
      state
    end
  end

  defp start_payload_builder(%{payload_builder: {slot, root, _}} = state, slot, root), do: state

  defp start_payload_builder(state, proposed_slot, head_root) do
    # TODO: handle reorgs and late blocks
    Logger.info("[Validator] Starting to build payload for slot #{proposed_slot}")

    case BlockBuilder.start_building_payload(proposed_slot, head_root) do
      {:ok, payload_id} ->
        %{state | payload_builder: {proposed_slot, head_root, payload_id}}

      {:error, reason} ->
        Logger.error(
          "[Validator] Failed to start building payload for slot #{proposed_slot}. Reason: #{reason}"
        )

        %{state | payload_builder: nil}
    end
  end

  defp maybe_propose(state, slot) do
    if proposer?(state, slot) do
      propose(state, slot)
    else
      state
    end
  end

  defp propose(%{payload_builder: nil} = state, _proposed_slot) do
    Logger.error("[Validator] Tried to propose a block without an execution payload")
    state
  end

  defp propose(
         %{root: head_root, validator: validator, payload_builder: payload_builder} = state,
         proposed_slot
       ) do
    {^proposed_slot, ^head_root, payload_id} = payload_builder

    build_result =
      BlockBuilder.build_block(
        %BuildBlockRequest{
          slot: proposed_slot,
          parent_root: head_root,
          proposer_index: validator.index,
          graffiti_message: @default_graffiti_message,
          privkey: validator.privkey
        },
        payload_id
      )

    case build_result do
      {:ok, {signed_block, blob_sidecars}} ->
        PendingBlocks.add_block(signed_block)
        publish_block(signed_block)
        Enum.each(blob_sidecars, &publish_sidecar/1)

      {:error, reason} ->
        Logger.error(
          "[Validator] Failed to build block for slot #{proposed_slot}. Reason: #{reason}"
        )
    end

    %{state | payload_builder: nil}
  end

  # TODO: there's a lot of repeated code here. We should move this to a separate module
  defp publish_block(signed_block) do
    {:ok, ssz_encoded} = Ssz.to_ssz(signed_block)
    {:ok, encoded_msg} = :snappyer.compress(ssz_encoded)
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)

    proposed_slot = signed_block.message.slot

    # TODO: we might want to send the block to ForkChoice
    case Libp2pPort.publish("/eth2/#{fork_context}/beacon_block/ssz_snappy", encoded_msg) do
      :ok ->
        Logger.info("[Validator] Proposed block for slot #{proposed_slot}")

      {:error, reason} ->
        Logger.error(
          "[Validator] Failed to publish block for slot #{proposed_slot}. Reason: #{reason}"
        )
    end
  end

  defp publish_sidecar(%Types.BlobSidecar{index: index} = sidecar) do
    {:ok, ssz_encoded} = Ssz.to_ssz(sidecar)
    {:ok, encoded_msg} = :snappyer.compress(ssz_encoded)
    fork_context = BeaconChain.get_fork_digest() |> Base.encode16(case: :lower)

    subnet_id = compute_subnet_for_blob_sidecar(index)

    case Libp2pPort.publish(
           "/eth2/#{fork_context}/blob_sidecar_#{subnet_id}/ssz_snappy",
           encoded_msg
         ) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[Validator] Failed to publish sidecar with index #{index}. Reason: #{reason}"
        )
    end
  end

  defp compute_subnet_for_blob_sidecar(blob_index) do
    rem(blob_index, ChainSpec.get("BLOB_SIDECAR_SUBNET_COUNT"))
  end
end
