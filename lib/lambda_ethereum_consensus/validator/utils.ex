defmodule LambdaEthereumConsensus.Validator.Utils do
  @moduledoc """
  Functions for performing validator duties.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.AttestationData
  alias Types.BeaconState

  @doc """
  Returns the index of a validator in the state's validator list given it's pubkey.
  """
  @spec fetch_validator_index(Types.BeaconState.t(), Bls.pubkey()) ::
          non_neg_integer() | nil
  def fetch_validator_index(state, pubkey) do
    Enum.find_index(state.validators, &(&1.pubkey == pubkey))
  end

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

    for {pubkey, index} <- Enum.with_index(sync_committee.pubkeys),
        pubkey == target_pubkey do
      div(index, Misc.sync_subcommittee_size())
    end
    |> Enum.dedup()
  end

  # `is_assigned_to_sync_committee` equivalent
  @spec assigned_to_sync_committee?(BeaconState.t(), Types.epoch(), Types.validator_index()) ::
          boolean()
  def assigned_to_sync_committee?(%BeaconState{} = state, epoch, validator_index) do
    target_pubkey = state.validators |> Map.get(validator_index, %{}) |> Map.get(:pubkey)

    target_pubkey && target_pubkey in Accessors.get_sync_committee_for_epoch!(state, epoch)
  end

  @doc """
  Returns a map of subcommittee index wich had a map of each validator present and
  their index in the subcommittee. E.g.:
  %{0 => %{0 => [0], 1 => [1, 2]}, 1 => %{2 => [0, 2], 0 => [1]}}
  For subcommittee 0, validator 0 is at index 0 and validator 1 is at index 1, 2
  For subcommittee 1, validator 2 is at index 0 and 2, validator 0 is at index 1
  ```
  """
  @spec participants_per_sync_subcommittee(BeaconState.t(), Types.epoch()) ::
          %{non_neg_integer() => [Bls.pubkey()]}
  def participants_per_sync_subcommittee(state, epoch) do
    state
    |> Accessors.get_sync_committee_for_epoch!(epoch)
    |> Map.get(:pubkeys)
    |> Enum.chunk_every(Misc.sync_subcommittee_size())
    |> Enum.with_index()
    |> Map.new(fn {pubkeys, i} ->
      indices_by_validator =
        pubkeys
        |> Enum.with_index()
        |> Enum.group_by(&fetch_validator_index(state, elem(&1, 0)), &elem(&1, 1))

      {i, indices_by_validator}
    end)
  end

  @spec get_sync_committee_selection_proof(
          BeaconState.t(),
          Types.slot(),
          non_neg_integer(),
          Bls.privkey()
        ) ::
          Types.bls_signature()
  def get_sync_committee_selection_proof(%BeaconState{} = state, slot, subcommittee_i, privkey) do
    domain_sc_selection_proof = Constants.domain_sync_committee_selection_proof()
    epoch = Misc.compute_epoch_at_slot(slot)
    domain = Accessors.get_domain(state, domain_sc_selection_proof, epoch)

    signing_data = %Types.SyncAggregatorSelectionData{
      slot: slot,
      subcommittee_index: subcommittee_i
    }

    signing_root =
      Misc.compute_signing_root(signing_data, Types.SyncAggregatorSelectionData, domain)

    {:ok, signature} = Bls.sign(privkey, signing_root)
    signature
  end

  # `is_sync_committee_aggregator` equivalent
  @spec sync_committee_aggregator?(Types.bls_signature()) :: boolean()
  def sync_committee_aggregator?(signature) do
    modulo =
      ChainSpec.get("SYNC_COMMITTEE_SIZE")
      |> div(Constants.sync_committee_subnet_count())
      |> div(Constants.target_aggregators_per_sync_subcommittee())
      |> max(1)

    SszEx.hash(signature)
    |> binary_part(0, 8)
    |> :binary.decode_unsigned(:little)
    |> rem(modulo) == 0
  end
end
