defmodule LambdaEthereumConsensus.Validator.Utils do
  @moduledoc """
  Functions for performing validator duties.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.AttestationData
  alias Types.BeaconState

  @doc """
    Compute the correct subnet for an attestation.
  """
  @spec compute_subnet_for_attestation(Types.uint64(), Types.slot(), Types.uint64()) ::
          Types.uint64()
  def compute_subnet_for_attestation(committees_per_slot, slot, committee_index) do
    slots_since_epoch_start = rem(slot, ChainSpec.get("SLOTS_PER_EPOCH"))
    committees_since_epoch_start = committees_per_slot * slots_since_epoch_start

    rem(committees_since_epoch_start + committee_index, ChainSpec.get("ATTESTATION_SUBNET_COUNT"))
  end

  @spec get_attestation_signature(BeaconState.t(), AttestationData.t(), Bls.privkey()) ::
          Types.bls_signature()
  def get_attestation_signature(%BeaconState{} = state, attestation_data, privkey) do
    domain_beacon_attester = Constants.domain_beacon_attester()
    domain = Accessors.get_domain(state, domain_beacon_attester, attestation_data.target.epoch)
    signing_root = Misc.compute_signing_root(attestation_data, domain)
    # Can't fail, unless privkey is invalid
    {:ok, signature} = Bls.sign(privkey, signing_root)
    signature
  end

  @spec get_slot_signature(BeaconState.t(), Types.slot(), Bls.privkey()) ::
          Types.bls_signature()
  def get_slot_signature(%BeaconState{} = state, slot, privkey) do
    domain_selection_proof = Constants.domain_selection_proof()
    epoch = Misc.compute_epoch_at_slot(slot)
    domain = Accessors.get_domain(state, domain_selection_proof, epoch)
    signing_root = Misc.compute_signing_root(slot, TypeAliases.slot(), domain)
    {:ok, signature} = Bls.sign(privkey, signing_root)
    signature
  end

  # `is_aggregator` equivalent
  @spec aggregator?(Types.bls_signature(), Types.commitee_index()) :: boolean()
  def aggregator?(slot_signature, committee_length) do
    target = Constants.target_aggregators_per_committee()
    modulo = committee_length |> div(target) |> max(1)

    SszEx.hash(slot_signature)
    |> binary_part(0, 8)
    |> :binary.decode_unsigned(:little)
    |> rem(modulo) == 0
  end

  @spec compute_subnets_for_sync_committee(BeaconState.t(), Types.validator_index()) :: [
          Types.uint64()
        ]
  def compute_subnets_for_sync_committee(%BeaconState{} = state, validator_index) do
    target_pubkey = state.validators[validator_index].pubkey
    current_epoch = Accessors.get_current_epoch(state)
    next_slot_epoch = Misc.compute_epoch_at_slot(state.slot + 1)
    current_sync_committee_period = Misc.compute_sync_committee_period(current_epoch)
    next_slot_sync_committee_period = Misc.compute_sync_committee_period(next_slot_epoch)

    sync_committee =
      if current_sync_committee_period == next_slot_sync_committee_period,
        do: state.current_sync_committee,
        else: state.next_sync_committee

    sync_committee_subnet_size =
      div(ChainSpec.get("SYNC_COMMITTEE_SIZE"), Constants.sync_committee_subnet_count())

    for {pubkey, index} <- Enum.with_index(sync_committee.pubkeys),
        pubkey == target_pubkey do
      div(index, sync_committee_subnet_size)
    end
    |> Enum.dedup()
  end

  # `is_assigned_to_sync_committee` equivalent
  @spec assigned_to_sync_committee?(BeaconState.t(), Types.epoch(), Types.validator_index()) ::
          boolean()
  def assigned_to_sync_committee?(%BeaconState{} = state, epoch, validator_index) do
    sync_committee_period = Misc.compute_sync_committee_period(epoch)
    current_epoch = Accessors.get_current_epoch(state)
    current_sync_committee_period = Misc.compute_sync_committee_period(current_epoch)
    next_sync_committee_period = current_sync_committee_period + 1

    pubkey = state.validators[validator_index].pubkey

    case sync_committee_period do
      ^current_sync_committee_period ->
        Enum.member?(state.current_sync_committee.pubkeys, pubkey)

      ^next_sync_committee_period ->
        Enum.member?(state.next_sync_committee.pubkeys, pubkey)

      _ ->
        raise ArgumentError,
              "Invalid epoch #{epoch}, should be in the current or next sync committee period"
    end
  end
end
