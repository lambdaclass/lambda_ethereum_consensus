defmodule LambdaEthereumConsensus.Validator.Duties do
  @moduledoc """
  Module to handle validator duties.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Validator
  alias LambdaEthereumConsensus.Validator.Utils
  alias LambdaEthereumConsensus.ValidatorSet
  alias Types.BeaconState

  require Logger

  @type attester_duty :: %{
          attested?: boolean(),
          should_aggregate?: boolean(),
          selection_proof: Bls.signature(),
          signing_domain: Types.domain(),
          subnet_id: Types.uint64(),
          slot: Types.slot(),
          validator_index: Types.validator_index(),
          committee_index: Types.uint64(),
          committee_length: Types.uint64(),
          index_in_committee: Types.uint64()
        }

  @type proposer_duty :: Types.slot()

  @type attester_duties :: %{Types.slot() => [attester_duty()]}
  @type proposer_duties :: %{Types.slot() => [proposer_duty()]}

  @type duties :: %{attesters: attester_duties(), proposers: proposer_duties()}

  @spec compute_proposers_for_epoch(BeaconState.t(), Types.epoch(), ValidatorSet.validators()) ::
          proposer_duties()
  def compute_proposers_for_epoch(%BeaconState{} = state, epoch, validators) do
    with {:ok, epoch} <- check_valid_epoch(state, epoch),
         {start_slot, end_slot} <- boundary_slots(epoch) do
      start_slot..end_slot
      |> Enum.flat_map(fn slot ->
        {:ok, proposer_index} = Accessors.get_beacon_proposer_index(state, slot)

        if Map.has_key?(validators, proposer_index),
          do: [{slot, proposer_index}],
          else: []
      end)
      |> Map.new()
    end
  end

  @spec compute_attesters_for_epoch(BeaconState.t(), Types.epoch(), ValidatorSet.validators()) ::
          attester_duties()
  def compute_attesters_for_epoch(%BeaconState{} = state, epoch, validators) do
    with {:ok, epoch} <- check_valid_epoch(state, epoch),
         {start_slot, end_slot} <- boundary_slots(epoch) do
      committee_count_per_slot = Accessors.get_committee_count_per_slot(state, epoch)

      start_slot..end_slot
      |> Enum.flat_map(fn slot ->
        0..(committee_count_per_slot - 1)
        |> Enum.flat_map(&compute_attester_duties(state, epoch, slot, validators, &1))
      end)
      |> Map.new()
    end
  end

  @spec compute_attester_duties(
          state :: BeaconState.t(),
          epoch :: Types.epoch(),
          slot :: Types.slot(),
          validators :: %{Types.validator_index() => Validator.t()},
          committee_index :: Types.uint64()
        ) :: [{Types.slot(), attester_duty()}]
  defp compute_attester_duties(state, epoch, slot, validators, committee_index) do
    case Accessors.get_beacon_committee(state, slot, committee_index) do
      {:ok, committee} ->
        compute_cometee_duties(state, epoch, slot, committee, committee_index, validators)

      {:error, _} ->
        []
    end
  end

  defp compute_cometee_duties(state, epoch, slot, committee, committee_index, validators) do
    committee
    |> Stream.with_index()
    |> Stream.flat_map(fn {validator_index, index_in_committee} ->
      case Map.get(validators, validator_index) do
        nil ->
          []

        validator ->
          [
            %{
              slot: slot,
              validator_index: validator_index,
              index_in_committee: index_in_committee,
              committee_length: length(committee),
              committee_index: committee_index,
              attested?: false
            }
            |> update_with_aggregation_duty(state, validator.keystore.privkey)
            |> update_with_subnet_id(state, epoch)
          ]
      end
    end)
    |> Enum.into([])
    |> case do
      [] -> []
      duties -> [{slot, duties}]
    end
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

  ############################
  # Helpers

  defp check_valid_epoch(state, epoch) do
    next_epoch = Accessors.get_current_epoch(state) + 1

    if epoch > next_epoch do
      {:error, "epoch must be <= next_epoch"}
    else
      {:ok, epoch}
    end
  end

  defp boundary_slots(epoch) do
    start_slot = Misc.compute_start_slot_at_epoch(epoch)
    end_slot = start_slot + ChainSpec.get("SLOTS_PER_EPOCH") - 1

    {start_slot, end_slot}
  end
end
