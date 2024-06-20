defmodule LambdaEthereumConsensus.Validator.Utils do
  @moduledoc """
  Functions for performing validator duties.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Types.Base.AttestationData
  alias LambdaEthereumConsensus.Types.Base.BeaconState

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
end
