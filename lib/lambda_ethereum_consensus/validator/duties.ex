defmodule LambdaEthereumConsensus.Validator.Duties do
  @moduledoc """
  Module to handle validator duties.
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Validator
  alias LambdaEthereumConsensus.Validator.Utils
  alias Types.BeaconState

  require Logger

  @type attester_duty :: %{
          attested?: boolean(),
          should_aggregate?: boolean(),
          selection_proof: Bls.signature(),
          signing_domain: Types.domain(),
          subnet_id: Types.uint64(),
          slot: Types.slot(),
          committee_index: Types.uint64(),
          committee_length: Types.uint64(),
          index_in_committee: Types.uint64()
        }
  @type proposer_duty :: Types.slot()

  @type attester_duties :: list(:not_computed | attester_duty())
  @type proposer_duties :: :not_computed | list(Types.slot())

  @type duties :: %{
          attester: attester_duties(),
          proposer: proposer_duties()
        }

  @spec empty_duties() :: duties()
  def empty_duties() do
    %{
      # Order is: previous epoch, current epoch, next epoch
      attester: [:not_computed, :not_computed, :not_computed],
      proposer: :not_computed
    }
  end

  @spec get_current_attester_duty(duties :: duties(), current_slot :: Types.slot()) ::
          attester_duty()
  def get_current_attester_duty(%{attester: attester_duties}, current_slot) do
    Enum.find(attester_duties, fn
      :not_computed -> false
      duty -> duty.slot == current_slot
    end)
  end

  @spec replace_attester_duty(
          duties :: duties(),
          duty :: attester_duty(),
          new_duty :: attester_duty()
        ) :: duties()
  def replace_attester_duty(duties, duty, new_duty) do
    attester_duties =
      Enum.map(duties.attester, fn
        ^duty -> new_duty
        d -> d
      end)

    %{duties | attester: attester_duties}
  end

  @spec log_duties(duties :: duties(), validator_index :: Types.validator_index()) :: :ok
  def log_duties(%{attester: attester_duties, proposer: proposer_duties}, validator_index) do
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

  @spec compute_proposer_duties(
          beacon_state :: BeaconState.t(),
          epoch :: Types.epoch(),
          validator_index :: Types.validator_index()
        ) :: proposer_duties()
  def compute_proposer_duties(beacon_state, epoch, validator_index) do
    start_slot = Misc.compute_start_slot_at_epoch(epoch)

    start_slot..(start_slot + ChainSpec.get("SLOTS_PER_EPOCH") - 1)
    |> Enum.flat_map(fn slot ->
      # Can't fail
      {:ok, proposer_index} = Accessors.get_beacon_proposer_index(beacon_state, slot)
      if proposer_index == validator_index, do: [slot], else: []
    end)
  end

  def maybe_update_duties(duties, beacon_state, epoch, validator) do
    attester_duties =
      maybe_update_attester_duties(duties.attester, beacon_state, epoch, validator)

    proposer_duties = compute_proposer_duties(beacon_state, epoch, validator.index)
    # To avoid edge-cases
    old_duty =
      case duties.proposer do
        :not_computed -> []
        old -> old |> Enum.reverse() |> Enum.take(1)
      end

    %{duties | attester: attester_duties, proposer: old_duty ++ proposer_duties}
  end

  defp maybe_update_attester_duties([epp, ep0, ep1], beacon_state, epoch, validator) do
    duties =
      Stream.with_index([ep0, ep1])
      |> Enum.map(fn
        {:not_computed, i} -> compute_attester_duties(beacon_state, epoch + i, validator)
        {d, _} -> d
      end)

    [epp | duties]
  end

  def shift_duties(%{attester: [_ep0, ep1, ep2]} = duties, epoch, current_epoch) do
    case current_epoch - epoch do
      1 -> %{duties | attester: [ep1, ep2, :not_computed]}
      2 -> %{duties | attester: [ep2, :not_computed, :not_computed]}
      _ -> %{duties | attester: [:not_computed, :not_computed, :not_computed]}
    end
  end

  @spec compute_attester_duties(
          beacon_state :: BeaconState.t(),
          epoch :: Types.epoch(),
          validator :: Validator.validator()
        ) :: attester_duty() | nil
  defp compute_attester_duties(beacon_state, epoch, validator) do
    # Can't fail
    {:ok, duty} = get_committee_assignment(beacon_state, epoch, validator.index)

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

  @doc """
    Return the committee assignment in the ``epoch`` for ``validator_index``.
    ``assignment`` returned is a tuple of the following form:
        * ``assignment[0]`` is the index of the validator in the committee
        * ``assignment[1]`` is the index to which the committee is assigned
        * ``assignment[2]`` is the slot at which the committee is assigned
    Return `nil` if no assignment.
  """
  @spec get_committee_assignment(BeaconState.t(), Types.epoch(), Types.validator_index()) ::
          {:ok, nil | attester_duty()} | {:error, String.t()}
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
        |> Stream.map(&compute_attester_duty(state, slot, validator_index, &1))
        |> Enum.find(&(not is_nil(&1)))
      end)
      |> Enum.find(&(not is_nil(&1)))
      |> then(&{:ok, &1})
    end
  end

  @spec compute_attester_duty(
          state :: BeaconState.t(),
          slot :: Types.slot(),
          validator_index :: Types.validator_index(),
          committee_index :: Types.uint64()
        ) :: attester_duty() | nil
  defp compute_attester_duty(state, slot, validator_index, committee_index) do
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
end
