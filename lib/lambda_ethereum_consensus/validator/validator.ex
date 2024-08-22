defmodule LambdaEthereumConsensus.Validator do
  @moduledoc """
  Module that performs validator duties.
  """
  require Logger

  defstruct [
    :index,
    :keystore,
    :payload_builder
  ]

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.P2P.Gossip
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.BlockStates
  alias LambdaEthereumConsensus.Store.CheckpointStates
  alias LambdaEthereumConsensus.Utils.BitField
  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Validator.BlockBuilder
  alias LambdaEthereumConsensus.Validator.BuildBlockRequest
  alias LambdaEthereumConsensus.Validator.Duties
  alias LambdaEthereumConsensus.Validator.Utils
  alias Types.Attestation

  @default_graffiti_message "Lambda, so gentle, so good"

  @type index :: non_neg_integer()

  @type t :: %__MODULE__{
          index: index() | nil,
          keystore: Keystore.t(),
          payload_builder: {Types.slot(), Types.root(), BlockBuilder.payload_id()} | nil
        }

  @spec new(Keystore.t(), Types.slot(), Types.root()) :: t()
  def new(keystore, head_slot, head_root) do
    epoch = Misc.compute_epoch_at_slot(head_slot)
    beacon = fetch_target_state_and_go_to_slot(epoch, head_slot, head_root)

    new(keystore, beacon)
  end

  @spec new(Keystore.t(), Types.BeaconState.t()) :: t()
  def new(keystore, beacon) do
    state = %__MODULE__{
      index: nil,
      keystore: keystore,
      payload_builder: nil
    }

    case fetch_validator_index(beacon, state.keystore.pubkey) do
      nil ->
        Logger.warning(
          "[Validator] Public key #{state.keystore.pubkey} not found in the validator set"
        )

        state

      validator_index ->
        log_debug(validator_index, "Setup completed")
        %{state | index: validator_index}
    end
  end

  ##########################
  # Target State

  @spec fetch_target_state_and_go_to_slot(Types.epoch(), Types.slot(), Types.root()) ::
          Types.BeaconState.t()
  def fetch_target_state_and_go_to_slot(epoch, slot, root) do
    epoch |> fetch_target_state(root) |> go_to_slot(slot)
  end

  defp fetch_target_state(epoch, root) do
    {:ok, state} = CheckpointStates.compute_target_checkpoint_state(epoch, root)
    state
  end

  defp go_to_slot(%{slot: old_slot} = state, slot) when old_slot == slot, do: state

  defp go_to_slot(%{slot: old_slot} = state, slot) when old_slot < slot do
    {:ok, st} = StateTransition.process_slots(state, slot)
    st
  end

  ##########################
  # Attestations

  @spec attest(t(), Duties.attester_duty(), Types.slot(), Types.root()) :: :ok
  def attest(%{index: validator_index, keystore: keystore}, current_duty, slot, head_root) do
    subnet_id = current_duty.subnet_id
    log_debug(validator_index, "attesting", slot: slot, subnet_id: subnet_id)

    attestation = produce_attestation(current_duty, slot, head_root, keystore.privkey)

    log_md = [slot: slot, attestation: attestation, subnet_id: subnet_id]

    debug_log_msg =
      "publishing attestation on committee index: #{current_duty.committee_index} | as #{current_duty.index_in_committee}/#{current_duty.committee_length - 1} and pubkey: #{LambdaEthereumConsensus.Utils.format_shorten_binary(keystore.pubkey)}"

    log_debug(validator_index, debug_log_msg, log_md)

    Gossip.Attestation.publish(subnet_id, attestation)
    |> log_info_result(validator_index, "published attestation", log_md)

    if current_duty.should_aggregate? do
      log_debug(validator_index, "collecting for future aggregation", log_md)

      Gossip.Attestation.collect(subnet_id, attestation)
      |> log_debug_result(validator_index, "collected attestation", log_md)
    end
  end

  @spec publish_aggregate(t(), Duties.attester_duty(), Types.slot()) ::
          :ok
  def publish_aggregate(%{index: validator_index, keystore: keystore}, duty, slot) do
    case Gossip.Attestation.stop_collecting(duty.subnet_id) do
      {:ok, attestations} ->
        log_md = [slot: slot, attestations: attestations]
        log_debug(validator_index, "publishing aggregate", log_md)

        aggregate_attestations(attestations)
        |> append_proof(duty.selection_proof, validator_index)
        |> append_signature(duty.signing_domain, keystore)
        |> Gossip.Attestation.publish_aggregate()
        |> log_info_result(validator_index, "published aggregate", log_md)

      {:error, reason} ->
        log_error(validator_index, "stop collecting attestations", reason)
        :ok
    end
  end

  defp aggregate_attestations(attestations) do
    # TODO: We need to check why we are producing duplicate attestations, this was generating invalid signatures
    unique_attestations = attestations |> Enum.uniq()

    aggregation_bits =
      unique_attestations
      |> Stream.map(&Map.fetch!(&1, :aggregation_bits))
      |> Enum.reduce(&BitField.bitwise_or/2)

    {:ok, signature} =
      unique_attestations |> Enum.map(&Map.fetch!(&1, :signature)) |> Bls.aggregate()

    %{List.first(attestations) | aggregation_bits: aggregation_bits, signature: signature}
  end

  defp append_proof(aggregate, proof, validator_index) do
    %Types.AggregateAndProof{
      aggregator_index: validator_index,
      aggregate: aggregate,
      selection_proof: proof
    }
  end

  defp append_signature(aggregate_and_proof, signing_domain, %{privkey: privkey}) do
    signing_root = Misc.compute_signing_root(aggregate_and_proof, signing_domain)
    {:ok, signature} = Bls.sign(privkey, signing_root)
    %Types.SignedAggregateAndProof{message: aggregate_and_proof, signature: signature}
  end

  defp produce_attestation(duty, slot, head_root, privkey) do
    %{
      index_in_committee: index_in_committee,
      committee_length: committee_length,
      committee_index: committee_index
    } = duty

    head_state = BlockStates.get_state_info!(head_root).beacon_state |> go_to_slot(slot)
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

  @spec fetch_validator_index(Types.BeaconState.t(), Bls.pubkey()) ::
          non_neg_integer() | nil
  defp fetch_validator_index(beacon, pubkey) do
    Enum.find_index(beacon.validators, &(&1.pubkey == pubkey))
  end

  ################################
  # Payload building and proposing

  @spec start_payload_builder(t(), Types.slot(), Types.root()) :: t()
  def start_payload_builder(%{payload_builder: {slot, root, _}} = state, slot, root), do: state

  def start_payload_builder(%{index: validator_index} = state, proposed_slot, head_root) do
    # TODO: handle reorgs and late blocks
    log_debug(validator_index, "starting building payload for slot #{proposed_slot}",
      root: head_root
    )

    case BlockBuilder.start_building_payload(proposed_slot, head_root) do
      {:ok, payload_id} ->
        log_info(validator_index, "payload built for slot #{proposed_slot}")

        %{state | payload_builder: {proposed_slot, head_root, payload_id}}

      {:error, reason} ->
        log_error(validator_index, "start building payload for slot #{proposed_slot}", reason)

        %{state | payload_builder: nil}
    end
  end

  @spec propose(t(), Types.slot(), Types.root()) :: t()
  def propose(
        %{
          index: validator_index,
          payload_builder: {proposed_slot, head_root, payload_id},
          keystore: keystore
        } = state,
        proposed_slot,
        head_root
      ) do
    log_debug(validator_index, "building block", slot: proposed_slot)

    build_result =
      BlockBuilder.build_block(
        %BuildBlockRequest{
          slot: proposed_slot,
          parent_root: head_root,
          proposer_index: validator_index,
          graffiti_message: @default_graffiti_message,
          privkey: keystore.privkey
        },
        payload_id
      )

    case build_result do
      {:ok, {signed_block, blob_sidecars}} ->
        publish_block(validator_index, signed_block)
        Enum.each(blob_sidecars, &publish_sidecar(validator_index, &1))

      {:error, reason} ->
        log_error(validator_index, "build block", reason, slot: proposed_slot)
    end

    %{state | payload_builder: nil}
  end

  def propose(%{payload_builder: nil} = state, _proposed_slot, _head_root) do
    log_error(state.index, "propose block", "lack of execution payload")
    state
  end

  def propose(state, proposed_slot, _head_root) do
    Logger.error(
      "[Validator] Skipping block proposal for slot #{proposed_slot} due to missing validator data"
    )

    state
  end

  # TODO: there's a lot of repeated code here. We should move this to a separate module
  defp publish_block(validator_index, signed_block) do
    {:ok, ssz_encoded} = Ssz.to_ssz(signed_block)
    {:ok, encoded_msg} = :snappyer.compress(ssz_encoded)
    fork_context = ForkChoice.get_fork_digest() |> Base.encode16(case: :lower)

    proposed_slot = signed_block.message.slot

    log_debug(validator_index, "publishing block", slot: proposed_slot)

    # TODO: we might want to send the block to ForkChoice
    Libp2pPort.publish("/eth2/#{fork_context}/beacon_block/ssz_snappy", encoded_msg)
    |> log_info_result(validator_index, "published block", slot: proposed_slot)
  end

  defp publish_sidecar(validator_index, %Types.BlobSidecar{index: index} = sidecar) do
    {:ok, ssz_encoded} = Ssz.to_ssz(sidecar)
    {:ok, encoded_msg} = :snappyer.compress(ssz_encoded)
    fork_context = ForkChoice.get_fork_digest() |> Base.encode16(case: :lower)

    subnet_id = compute_subnet_for_blob_sidecar(index)

    log_debug(validator_index, "publishing sidecar", sidecar_index: index)

    Libp2pPort.publish("/eth2/#{fork_context}/blob_sidecar_#{subnet_id}/ssz_snappy", encoded_msg)
    |> log_debug_result(validator_index, "published sidecar", sidecar_index: index)
  end

  defp compute_subnet_for_blob_sidecar(blob_index) do
    rem(blob_index, ChainSpec.get("BLOB_SIDECAR_SUBNET_COUNT"))
  end

  ################################
  # Log Helpers

  defp log_info_result(result, index, message, metadata),
    do: log_result(result, :info, index, message, metadata)

  defp log_debug_result(result, index, message, metadata),
    do: log_result(result, :debug, index, message, metadata)

  defp log_result(:ok, :info, index, message, metadata), do: log_info(index, message, metadata)
  defp log_result(:ok, :debug, index, message, metadata), do: log_debug(index, message, metadata)

  defp log_info(index, message, metadata \\ []),
    do: Logger.info("[Validator] #{index} #{message}", metadata)

  defp log_debug(index, message, metadata \\ []),
    do: Logger.debug("[Validator] #{index} #{message}", metadata)

  defp log_error(index, message, reason, metadata \\ []),
    do: Logger.error("[Validator] #{index} Failed to #{message}. Reason: #{reason}", metadata)
end
