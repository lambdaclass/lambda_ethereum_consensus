defmodule LambdaEthereumConsensus.ValidatorSet do
  @moduledoc """
  Module that holds the set of validators and their states,
  it also manages the validator's duties as bitmaps to
  simplify the delegation of work.
  """

  defstruct slot: nil,
            head_root: nil,
            duties: %{},
            subscribed_subnets: %{attesters: MapSet.new(), sync_committees: MapSet.new()},
            validators: %{}

  require Logger

  alias LambdaEthereumConsensus.P2P.Gossip.Attestation
  alias LambdaEthereumConsensus.P2P.Gossip.SyncCommittee
  alias LambdaEthereumConsensus.StateTransition
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.CheckpointStates
  alias LambdaEthereumConsensus.Validator
  alias LambdaEthereumConsensus.Validator.Duties

  @type validators :: %{Validator.index() => Validator.t()}

  @type t :: %__MODULE__{
          slot: Types.slot(),
          head_root: Types.root() | nil,
          duties: %{Types.epoch() => Duties.duties()},
          subscribed_subnets: %{attesters: Duties.subnets(), sync_committees: Duties.subnets()},
          validators: validators()
        }

  @doc "Check if the duties for the given epoch are already computed."
  defguard is_duties_computed(set, epoch)
           when is_map(set.duties) and not is_nil(:erlang.map_get(epoch, set.duties))

  @doc """
  Initiate the set of validators, given the slot and head root.
  """
  @spec init(Types.slot(), Types.root()) :: t()
  def init(slot, head_root) do
    config = Application.get_env(:lambda_ethereum_consensus, __MODULE__, [])
    keystore_dir = Keyword.get(config, :keystore_dir)
    keystore_pass_dir = Keyword.get(config, :keystore_pass_dir)

    initial_keystores = Keystore.decode_validator_keystores(keystore_dir, keystore_pass_dir)

    setup_validators(%__MODULE__{}, slot, head_root, initial_keystores)
  end

  defp setup_validators(set, _s, _r, []) do
    Logger.warning("[ValidatorSet] No keystores provided. Validator's wont start.")

    set
  end

  defp setup_validators(set, slot, head_root, validator_keystores) do
    epoch = Misc.compute_epoch_at_slot(slot)
    beacon = fetch_target_state_and_go_to_slot(epoch, slot, head_root)

    new_validators =
      Map.new(validator_keystores, fn keystore ->
        validator = Validator.new(keystore, beacon)
        {validator.index, validator}
      end)

    Logger.info("[Validator] Initialized #{Enum.count(new_validators)} validators")

    %{set | validators: Map.merge(set.validators, new_validators)}
    |> update_state(epoch, slot, head_root)
  end

  ##########################
  # Validator management

  @doc """
  Get the validators keystores
  """
  @spec get_keystores(t()) :: list(Keystore.t())
  def get_keystores(%{validators: validators}),
    do: Enum.map(validators, fn {_index, validator} -> validator.keystore end)

  @doc """
  Add a validator to the set.
  """
  @spec add_validator(t(), Keystore.t()) :: t()
  def add_validator(%{slot: slot, head_root: head_root} = set, validator_keystore),
    do: setup_validators(set, slot, head_root, [validator_keystore])

  @doc """
  Remove a validator from the set.
  """
  @spec remove_validator(t(), Validator.index()) :: {:ok, t()} | {:error, :validator_not_found}
  def remove_validator(%{validators: validators} = set, pubkey) do
    validators
    |> Enum.find(fn {_index, validator} -> validator.keystore.pubkey == pubkey end)
    |> case do
      {index, _validator} ->
        updated_validators = Map.delete(set.validators, index)
        {:ok, Map.put(set, :validators, updated_validators)}

      _ ->
        {:error, :validator_not_found}
    end
  end

  ##########################
  # Notify Tick & Head

  @doc """
  Notify all validators of a new head.
  """
  @spec notify_head(t(), Types.slot(), Types.root()) :: t()
  def notify_head(%{validators: validators} = set, slot, head_root) when validators == %{},
    do: update_state(set, Misc.compute_epoch_at_slot(slot), slot, head_root)

  def notify_head(set, slot, head_root) do
    Logger.debug("[ValidatorSet] New Head", root: head_root, slot: slot)
    epoch = Misc.compute_epoch_at_slot(slot)

    # TODO: this doesn't take into account reorgs
    set
    |> update_state(epoch, slot, head_root)
    |> maybe_attests(epoch, slot, head_root)
    |> maybe_build_payload(slot + 1, head_root)
    |> maybe_sync_committee_broadcasts(slot, head_root)
  end

  @doc """
  Notify all validators of a new tick.
  """
  @spec notify_tick(t(), tuple()) :: t()
  def notify_tick(%{validators: validators} = set, _slot_data) when validators == %{},
    do: set

  def notify_tick(%{head_root: head_root} = set, {slot, third} = slot_data) do
    Logger.debug("[ValidatorSet] Tick #{inspect(third)}", root: head_root, slot: slot)
    epoch = Misc.compute_epoch_at_slot(slot)

    set
    |> update_state(epoch, slot, head_root)
    |> process_tick(epoch, slot_data)
  end

  defp process_tick(%{head_root: head_root} = set, epoch, {slot, :first_third}) do
    set
    |> maybe_resubscribe_to_subnets(epoch, slot)
    |> maybe_propose(epoch, slot, head_root)
  end

  defp process_tick(%{head_root: head_root} = set, epoch, {slot, :second_third}) do
    set
    |> maybe_attests(epoch, slot, head_root)
    |> maybe_build_payload(slot + 1, head_root)
    |> maybe_sync_committee_broadcasts(slot, head_root)
  end

  defp process_tick(set, epoch, {slot, :last_third}) do
    set
    |> maybe_publish_attestation_aggregates(epoch, slot)
    |> maybe_publish_sync_aggregates(slot)
  end

  ##############################
  # State update

  defp update_state(set, epoch, slot, head_root) do
    set
    |> update_slot_and_head(slot, head_root)
    |> compute_duties(epoch, slot, head_root)
  end

  defp update_slot_and_head(%{slot: slot, head_root: head_root} = set, slot, head_root), do: set
  defp update_slot_and_head(set, slot, head_root), do: %{set | slot: slot, head_root: head_root}

  defp compute_duties(%{validators: validators} = set, _epoch, _slot, _head_root)
       when validators == %{},
       do: set

  defp compute_duties(set, epoch, _slot, _head_root)
       when is_duties_computed(set, epoch) and is_duties_computed(set, epoch + 1),
       do: set

  defp compute_duties(set, epoch, slot, head_root) do
    epochs_to_calculate =
      [{epoch, slot}, {epoch + 1, Misc.compute_start_slot_at_epoch(epoch + 1)}]
      |> Enum.reject(&Map.has_key?(set.duties, elem(&1, 0)))

    set.duties
    |> Duties.compute_duties_for_epochs(epochs_to_calculate, head_root, set.validators)
    |> merge_duties_and_prune(epoch, set)
  end

  defp merge_duties_and_prune(new_duties, current_epoch, set) do
    set.duties
    # Remove duties from epoch - 2 or older
    |> Map.reject(fn {old_epoch, _} -> old_epoch < current_epoch - 1 end)
    |> Map.merge(new_duties)
    |> then(fn current_duties -> %{set | duties: current_duties} end)
  end

  ##############################
  # Block proposal

  defp maybe_build_payload(%{validators: validators} = set, slot, head_root) do
    # We calculate payloads from a previous slot, we need to recompute the epoch
    epoch = Misc.compute_epoch_at_slot(slot)

    case Duties.current_proposer(set.duties, epoch, slot) do
      nil ->
        set

      validator_index ->
        validators
        |> Map.update!(validator_index, &Validator.start_payload_builder(&1, slot, head_root))
        |> update_validators(set)
    end
  end

  defp maybe_propose(%{validators: validators} = set, epoch, slot, head_root) do
    case Duties.current_proposer(set.duties, epoch, slot) do
      nil ->
        set

      validator_index ->
        validators
        |> Map.update!(validator_index, &Validator.propose(&1, slot, head_root))
        |> update_validators(set)
    end
  end

  defp update_validators(new_validators, set), do: %{set | validators: new_validators}

  ##############################
  # Sync committee

  defp maybe_sync_committee_broadcasts(set, slot, head_root) do
    # Sync committee is broadcasted for the next slot, so we take the duties for the correct epoch.
    epoch = Misc.compute_epoch_at_slot(slot + 1)

    case Duties.current_sync_committee(set.duties, epoch, slot) do
      [] ->
        set

      sync_committee_duties ->
        sync_committee_duties
        |> Enum.map(&sync_committee_broadcast(&1, slot, head_root, set.validators))
        |> update_duties(set, epoch, :sync_committees, slot)
    end
  end

  defp maybe_publish_sync_aggregates(set, slot) do
    # Sync committee is broadcasted for the next slot, so we take the duties for the correct epoch.
    epoch = Misc.compute_epoch_at_slot(slot + 1)

    case Duties.current_sync_aggregators(set.duties, epoch, slot) do
      [] ->
        set

      aggregator_duties ->
        participants = Duties.sync_subcommittee_participants(set.duties, epoch)

        aggregator_duties
        |> Enum.map(&publish_sync_aggregate(&1, participants, slot, set.validators))
        |> update_duties(set, epoch, :sync_committees, slot)
    end
  end

  defp sync_committee_broadcast(duty, slot, head_root, validators) do
    validators
    |> Map.get(duty.validator_index)
    |> Validator.sync_committee_message_broadcast(duty, slot, head_root)

    Duties.sync_committee_broadcasted(duty)
  end

  defp publish_sync_aggregate(duty, participants, slot, validators) do
    validators
    |> Map.get(duty.validator_index)
    |> Validator.publish_sync_aggregate(duty, participants, slot)

    Duties.sync_committee_aggregated(duty)
  end

  ##############################
  # Attestation

  defp maybe_attests(set, epoch, slot, head_root) do
    case Duties.current_attesters(set.duties, epoch, slot) do
      [] ->
        set

      attester_duties ->
        head_state = fetch_target_state_and_go_to_slot(epoch, slot, head_root)

        attester_duties
        |> Enum.map(&attest(&1, head_state, slot, head_root, set.validators))
        |> update_duties(set, epoch, :attesters, slot)
    end
  end

  defp maybe_publish_attestation_aggregates(set, epoch, slot) do
    case Duties.current_aggregators(set.duties, epoch, slot) do
      [] ->
        set

      aggregator_duties ->
        aggregator_duties
        |> Enum.map(&publish_aggregate(&1, slot, set.validators))
        |> update_duties(set, epoch, :attesters, slot)
    end
  end

  defp attest(duty, head_state, slot, head_root, validators) do
    validators
    |> Map.get(duty.validator_index)
    |> Validator.attest(duty, head_state, slot, head_root)

    Duties.attested(duty)
  end

  defp publish_aggregate(duty, slot, validators) do
    validators
    |> Map.get(duty.validator_index)
    |> Validator.publish_aggregate(duty, slot)

    Duties.aggregated(duty)
  end

  defp update_duties(new_duties, set, epoch, kind, slot) do
    set.duties
    |> Duties.update_duties!(kind, epoch, slot, new_duties)
    |> then(&%{set | duties: &1})
  end

  ##########################
  # Subnets

  defp maybe_resubscribe_to_subnets(set, epoch, slot) do
    %{subscribed_subnets: %{attesters: old_att_subnets, sync_committees: old_sync_subnets}} = set

    %{attesters: new_att_subnets, sync_committees: new_sync_subnets} =
      Duties.current_subnets(set.duties, epoch, slot)

    unsubscribe_att = MapSet.difference(old_att_subnets, new_att_subnets)
    unsubscribe_sync = MapSet.difference(old_sync_subnets, new_sync_subnets)

    Enum.each(unsubscribe_att, &Attestation.unsubscribe/1)
    Enum.each(unsubscribe_sync, &SyncCommittee.unsubscribe/1)

    subscribe_att = MapSet.difference(new_att_subnets, old_att_subnets)
    subscribe_sync = MapSet.difference(new_sync_subnets, old_sync_subnets)

    Enum.each(subscribe_att, &Attestation.subscribe/1)
    Enum.each(subscribe_sync, &SyncCommittee.subscribe/1)

    %{set | subscribed_subnets: %{attesters: new_att_subnets, sync_committees: new_sync_subnets}}
  end

  ##########################
  # Target State
  # TODO: (#1278) This should be taken from the store as noted by arkenan.
  @spec fetch_target_state_and_go_to_slot(Types.epoch(), Types.slot(), Types.root()) ::
          Types.BeaconState.t()
  def fetch_target_state_and_go_to_slot(epoch, slot, root) do
    {time, result} =
      :timer.tc(fn ->
        epoch |> fetch_target_state(root) |> go_to_slot(slot)
      end)

    Logger.debug("[Validator] Fetched target state in #{time / 1_000}ms",
      epoch: epoch,
      slot: slot
    )

    result
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
end
