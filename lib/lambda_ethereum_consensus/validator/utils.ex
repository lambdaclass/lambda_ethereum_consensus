defmodule LambdaEthereumConsensus.Validator.Utils do
  @moduledoc """
  Functions for performing validator duties.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.AttestationData
  alias Types.BeaconState

  @type duty() :: %{
          index_in_committee: Types.uint64(),
          committee_length: Types.uint64(),
          committee_index: Types.uint64(),
          slot: Types.slot()
        }

  @doc """
    Return the committee assignment in the ``epoch`` for ``validator_index``.
    ``assignment`` returned is a tuple of the following form:
        * ``assignment[0]`` is the index of the validator in the committee
        * ``assignment[1]`` is the index to which the committee is assigned
        * ``assignment[2]`` is the slot at which the committee is assigned
    Return `nil` if no assignment.
  """
  @spec get_committee_assignment(BeaconState.t(), Types.epoch(), Types.validator_index()) ::
          {:ok, nil | duty()} | {:error, String.t()}
  def get_committee_assignment(%BeaconState{} = state, epoch, validator_index) do
    next_epoch = Accessors.get_current_epoch(state) + 1

    if epoch > next_epoch do
      {:error, "epoch must be <= next_epoch"}
    else
      start_slot = Misc.compute_start_slot_at_epoch(epoch)
      committee_count_per_slot = Accessors.get_committee_count_per_slot(state, epoch)
      end_slot = start_slot + ChainSpec.get("SLOTS_PER_EPOCH")

      start_slot..end_slot
      |> Stream.map(fn slot ->
        0..(committee_count_per_slot - 1)
        |> Stream.map(&compute_duties(state, slot, validator_index, &1))
        |> Enum.find(&(not is_nil(&1)))
      end)
      |> Enum.find(&(not is_nil(&1)))
      |> then(&{:ok, &1})
    end
  end

  defp compute_duties(state, slot, validator_index, committee_index) do
    case Accessors.get_beacon_committee(state, slot, committee_index) do
      {:ok, committee} ->
        case Enum.find_index(committee, &(&1 == validator_index)) do
          nil ->
            nil

          index ->
            %{
              index_in_committee: index,
              committee_length: length(committee),
              committee_index: committee_index,
              slot: slot
            }
        end

      {:error, _} ->
        nil
    end
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
end
