defmodule LambdaEthereumConsensus.Validator.Duties do
  @moduledoc """
  Module to handle validator duties.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
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
          validator_index: Types.validator_index(),
          committee_index: Types.uint64(),
          committee_length: Types.uint64(),
          index_in_committee: Types.uint64()
        }

  @type proposer_duty :: Types.validator_index()

  @type sync_committee_duty :: %{
          last_slot_broadcasted: Types.slot(),
          subnet_ids: [Types.uint64()],
          validator_index: Types.validator_index()
        }

  @type attester_duties :: [attester_duty()]
  @type proposer_duties :: [proposer_duty()]
  @type sync_committee_duties :: [sync_committee_duty()]

  @type attester_duties_per_slot :: %{Types.slot() => attester_duties()}
  @type proposer_duties_per_slot :: %{Types.slot() => proposer_duties()}

  @type kind :: :proposers | :attesters | :sync_committees
  @type duties :: %{
          kind() =>
            attester_duties_per_slot() | proposer_duties_per_slot() | sync_committee_duties()
        }

  ############################
  # Accessors

  @spec current_proposer(duties(), Types.epoch(), Types.slot()) :: proposer_duty() | nil
  def current_proposer(duties, epoch, slot),
    do: get_in(duties, [epoch, :proposers, slot])

  @spec current_sync_committee(duties(), Types.epoch(), Types.slot()) ::
          sync_committee_duties()
  def current_sync_committee(duties, epoch, slot) do
    for %{last_slot_broadcasted: last_slot} = duty <- sync_committee(duties, epoch),
        last_slot < slot do
      duty
    end
  end

  @spec current_attesters(duties(), Types.epoch(), Types.slot()) :: attester_duties()
  def current_attesters(duties, epoch, slot) do
    for %{attested?: false} = duty <- attesters(duties, epoch, slot) do
      duty
    end
  end

  @spec current_aggregators(duties(), Types.epoch(), Types.slot()) :: attester_duties()
  def current_aggregators(duties, epoch, slot) do
    for %{should_aggregate?: true} = duty <- attesters(duties, epoch, slot) do
      duty
    end
  end

  defp sync_committee(duties, epoch), do: get_in(duties, [epoch, :sync_committees]) || []
  defp attesters(duties, epoch, slot), do: get_in(duties, [epoch, :attesters, slot]) || []

  ############################
  # Update functions

  @spec update_duties!(
          duties(),
          kind(),
          Types.epoch(),
          Types.slot(),
          attester_duties() | proposer_duties()
        ) :: duties()
  def update_duties!(duties, :sync_committees, epoch, _slot, updated),
    do: put_in(duties, [epoch, :sync_committees], updated)

  def update_duties!(duties, kind, epoch, slot, updated),
    do: put_in(duties, [epoch, kind, slot], updated)

  @spec attested(attester_duty()) :: attester_duty()
  def attested(duty), do: Map.put(duty, :attested?, true)

  @spec aggregated(attester_duty()) :: attester_duty()
  def aggregated(duty), do: Map.put(duty, :should_aggregate?, false)

  @spec sync_committee_broadcasted(sync_committee_duty(), Types.slot()) :: sync_committee_duty()
  def sync_committee_broadcasted(duty, slot), do: Map.put(duty, :last_slot_broadcasted, slot)

  ############################
  # Main functions

  @spec compute_proposers_for_epoch(BeaconState.t(), Types.epoch(), ValidatorSet.validators()) ::
          proposer_duties_per_slot()
  def compute_proposers_for_epoch(%BeaconState{} = state, epoch, validators) do
    with {:ok, epoch} <- check_valid_epoch(state, epoch),
         {start_slot, end_slot} <- boundary_slots(epoch) do
      for slot <- start_slot..end_slot,
          {:ok, proposer_index} = Accessors.get_beacon_proposer_index(state, slot),
          Map.has_key?(validators, proposer_index),
          into: %{} do
        {slot, proposer_index}
      end
    end
  end

  @spec compute_current_sync_committees(BeaconState.t(), ValidatorSet.validators()) ::
          sync_committee_duties()
  def compute_current_sync_committees(%BeaconState{} = state, validators) do
    for validator_index <- Map.keys(validators),
        subnet_ids = Utils.compute_subnets_for_sync_committee(state, validator_index) do
      %{
        last_slot_broadcasted: -1,
        subnet_ids: subnet_ids,
        validator_index: validator_index
      }
    end
  end

  @spec compute_attesters_for_epoch(BeaconState.t(), Types.epoch(), ValidatorSet.validators()) ::
          attester_duties_per_slot()
  def compute_attesters_for_epoch(%BeaconState{} = state, epoch, validators) do
    with {:ok, epoch} <- check_valid_epoch(state, epoch),
         {start_slot, end_slot} <- boundary_slots(epoch) do
      committee_count_per_slot = Accessors.get_committee_count_per_slot(state, epoch)

      for slot <- start_slot..end_slot,
          committee_i <- 0..(committee_count_per_slot - 1),
          reduce: %{} do
        acc ->
          new_duties = compute_duties_per_committee(state, epoch, slot, validators, committee_i)
          Map.update(acc, slot, new_duties, &(new_duties ++ &1))
      end
    end
  end

  defp compute_duties_per_committee(state, epoch, slot, validators, committee_index) do
    case Accessors.get_beacon_committee(state, slot, committee_index) do
      {:ok, committee} ->
        for {validator_index, index_in_committee} <- Enum.with_index(committee),
            validator = Map.get(validators, validator_index) do
          %{
            validator_index: validator_index,
            index_in_committee: index_in_committee,
            committee_length: length(committee),
            committee_index: committee_index,
            attested?: false
          }
          |> update_with_aggregation_duty(state, slot, validator.keystore.privkey)
          |> update_with_subnet_id(state, epoch, slot)
        end

      {:error, _} ->
        []
    end
  end

  defp update_with_aggregation_duty(duty, beacon_state, slot, privkey) do
    proof = Utils.get_slot_signature(beacon_state, slot, privkey)

    if Utils.aggregator?(proof, duty.committee_length) do
      epoch = Misc.compute_epoch_at_slot(slot)
      domain = Accessors.get_domain(beacon_state, Constants.domain_aggregate_and_proof(), epoch)

      Map.put(duty, :should_aggregate?, true)
      |> Map.put(:selection_proof, proof)
      |> Map.put(:signing_domain, domain)
    else
      Map.put(duty, :should_aggregate?, false)
    end
  end

  defp update_with_subnet_id(duty, beacon_state, epoch, slot) do
    committees_per_slot = Accessors.get_committee_count_per_slot(beacon_state, epoch)

    subnet_id =
      Utils.compute_subnet_for_attestation(committees_per_slot, slot, duty.committee_index)

    Map.put(duty, :subnet_id, subnet_id)
  end

  ############################
  # Helpers

  @spec log_duties_for_epoch(duties(), Types.epoch()) :: :ok
  def log_duties_for_epoch(%{proposers: proposers, attesters: attesters}, epoch) do
    Logger.info("[Duties] Proposers for epoch #{epoch} (slot=>validator): #{inspect(proposers)}")

    for {slot, att_duties} <- attesters do
      Logger.info("[Duties] Attesters for epoch: #{epoch}, slot #{slot}:")

      for %{
            index_in_committee: ic,
            committee_index: ci,
            committee_length: cl,
            subnet_id: si,
            should_aggregate?: agg,
            validator_index: vi
          } <- att_duties do
        Logger.info([
          "[Duties] Validator: #{vi}, will attest in committee #{ci} ",
          "as #{ic}/#{cl - 1} in subnet: #{si}#{if agg, do: " and should Aggregate"}."
        ])
      end
    end

    :ok
  end

  def log_duties_for_epoch(_duties, epoch),
    do: Logger.info("[Duties] No duties for epoch: #{epoch}.")

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
