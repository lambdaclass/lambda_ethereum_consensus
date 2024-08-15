defmodule LambdaEthereumConsensus.ValidatorSet do
  @moduledoc """
  Module that holds the set of validators and their states,
  it also manages the validator's duties as bitmaps to
  simplify the delegation of work.
  """

  defstruct head_root: nil, duties: %{}, validators: []

  require Logger

  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Validator
  alias LambdaEthereumConsensus.Validator.Duties

  @type validators :: %{Validator.index() => Validator.t()}

  @type t :: %__MODULE__{
          head_root: Types.root() | nil,
          duties: %{
            Types.epoch() => %{
              proposers: Duties.proposer_duties(),
              attesters: Duties.attester_duties()
            }
          },
          validators: validators()
        }

  @doc """
  Initiate the set of validators, given the slot and head root.
  """
  @spec init(Types.slot(), Types.root()) :: t()
  def init(slot, head_root) do
    config = Application.get_env(:lambda_ethereum_consensus, __MODULE__, [])
    keystore_dir = Keyword.get(config, :keystore_dir)
    keystore_pass_dir = Keyword.get(config, :keystore_pass_dir)

    setup_validators(slot, head_root, keystore_dir, keystore_pass_dir)
  end

  @doc """
  Notify all validators of a new head.
  """
  @spec notify_head(t(), Types.slot(), Types.root()) :: t()
  def notify_head(set, slot, head_root) do
    # TODO: Just for testing purposes, remove it later
    Logger.info("[Validator] Notifying all Validators with new_head", root: head_root, slot: slot)
    epoch = Misc.compute_epoch_at_slot(slot)

    set
    |> update_state(epoch, slot, head_root)
    |> attest(epoch, slot, head_root)
    |> build_next_payload(epoch, slot, head_root)
  end

  @doc """
  Notify all validators of a new tick.
  """
  @spec notify_tick(t(), tuple()) :: t()
  def notify_tick(%{head_root: head_root} = set, {slot, third} = slot_data) do
    # TODO: Just for testing purposes, remove it later
    Logger.info("[Validator] Notifying all Validators with notify_tick: #{inspect(third)}",
      root: head_root,
      slot: slot
    )

    epoch = Misc.compute_epoch_at_slot(slot)

    set
    |> update_state(epoch, slot, head_root)
    |> process_tick(epoch, slot_data)
  end

  defp process_tick(%{head_root: head_root} = set, epoch, {slot, :first_third}),
    do: propose(set, epoch, slot, head_root)

  defp process_tick(%{head_root: head_root} = set, epoch, {slot, :second_third}) do
    set
    |> attest(epoch, slot, head_root)
    |> build_next_payload(epoch, slot, head_root)
  end

  defp process_tick(set, epoch, {slot, :last_third}),
    do: publish_aggregate(set, epoch, slot)

  ##############################
  # Setup

  defp setup_validators(_s, _r, keystore_dir, keystore_pass_dir)
       when is_nil(keystore_dir) or is_nil(keystore_pass_dir) do
    Logger.warning(
      "[Validator] No keystore_dir or keystore_pass_dir provided. Validators won't start."
    )

    %__MODULE__{}
  end

  defp setup_validators(slot, head_root, keystore_dir, keystore_pass_dir) do
    validator_keystores = decode_validator_keystores(keystore_dir, keystore_pass_dir)
    epoch = Misc.compute_epoch_at_slot(slot)

    # This will be removed later when refactoring Validator new
    beacon = Validator.fetch_target_state_and_go_to_slot(epoch, slot, head_root)

    validators =
      Map.new(validator_keystores, fn keystore ->
        validator = Validator.new(keystore, beacon)
        {validator.index, validator}
      end)

    Logger.info("[Validator] Initialized #{Enum.count(validators)} validators")

    %__MODULE__{validators: validators}
    |> update_state(epoch, slot, head_root)
  end

  ##############################
  # State update

  defp update_state(set, epoch, slot, head_root) do
    set
    |> update_head(head_root)
    |> compute_duties(epoch, slot, head_root)
  end

  defp update_head(%{head_root: head_root} = set, head_root), do: set
  defp update_head(set, head_root), do: %{set | head_root: head_root}

  defp compute_duties(set, epoch, _slot, _head_root)
       when not is_nil(:erlang.map_get(epoch, set.duties)),
       do: set

  defp compute_duties(set, epoch, slot, head_root) do
    epoch
    |> Validator.fetch_target_state_and_go_to_slot(slot, head_root)
    |> compute_duties_for_epoch!(epoch, set.validators)
    |> merge_duties_and_prune(epoch, set)
  end

  defp compute_duties_for_epoch!(beacon, epoch, validators) do
    proposers = Duties.compute_proposers_for_epoch(beacon, epoch, validators)
    attesters = Duties.compute_attesters_for_epoch(beacon, epoch, validators)

    Logger.info(
      "[Validator] Proposer duties for epoch #{epoch} are: #{inspect(proposers, pretty: true)}"
    )

    Logger.info(
      "[Validator] Attester duties for epoch #{epoch} are: #{inspect(attesters, pretty: true)}"
    )

    %{epoch => %{proposers: proposers, attesters: attesters}}
  end

  defp merge_duties_and_prune(new_duties, epoch, set) do
    set.duties
    # Remove duties from epoch - 2 or older
    |> Map.reject(fn {old_epoch, _} -> old_epoch < epoch - 2 end)
    |> Map.merge(new_duties)
    |> then(fn current_duties -> %{set | duties: current_duties} end)
  end

  ##############################
  # Attestation and proposal

  defp attest(set, epoch, slot, head_root) do
    case current_attesters(set, epoch, slot) do
      [] ->
        set

      attesters ->
        Enum.map(attesters, fn {validator, duty} ->
          Validator.attest(validator, duty, head_root)

          # Duty.attested(duty)
          %{duty | attested?: true}
        end)
        |> then(&%{set | duties: put_in(set.duties, [epoch, :attesters, slot], &1)})
    end
  end

  defp publish_aggregate(set, epoch, slot) do
    case current_aggregators(set, epoch, slot) do
      [] ->
        set

      aggregators ->
        Enum.map(aggregators, fn {validator, duty} ->
          Validator.publish_aggregate(duty, validator.index, validator.keystore)

          # Duty.aggregated(duty)
          %{duty | should_aggregate?: false}
        end)
        |> then(&%{set | duties: put_in(set.duties, [epoch, :attesters, slot], &1)})
    end
  end

  defp build_next_payload(%{validators: validators} = set, epoch, slot, head_root) do
    set
    |> proposer(epoch, slot + 1)
    |> case do
      nil ->
        set

      validator_index ->
        validators
        |> Map.update!(validator_index, &Validator.start_payload_builder(&1, slot + 1, head_root))
        |> then(&%{set | validators: &1})
    end
  end

  defp propose(%{validators: validators} = set, epoch, slot, head_root) do
    set
    |> proposer(epoch, slot)
    |> case do
      nil ->
        set

      validator_index ->
        validators
        |> Map.update!(validator_index, &Validator.propose(&1, slot, head_root))
        |> then(&%{set | validators: &1})
    end
  end

  ##############################
  # Helpers

  defp current_attesters(set, epoch, slot) do
    set
    |> attesters(epoch, slot)
    |> Enum.flat_map(fn
      %{attested?: false} = duty -> [{Map.get(set.validators, duty.validator_index), duty}]
      _ -> []
    end)
  end

  defp current_aggregators(set, epoch, slot) do
    set
    |> attesters(epoch, slot)
    |> Enum.flat_map(fn
      %{should_aggregate?: true} = duty -> [{Map.get(set.validators, duty.validator_index), duty}]
      _ -> []
    end)
  end

  defp proposer(set, epoch, slot), do: get_in(set.duties, [epoch, :proposers, slot])
  defp attesters(set, epoch, slot), do: get_in(set.duties, [epoch, :attesters, slot]) || []

  @doc """
    Get validator keystores from the keystore directory.
    This function expects two files for each validator:
      - <keystore_dir>/<public_key>.json
      - <keystore_pass_dir>/<public_key>.txt
  """
  @spec decode_validator_keystores(binary(), binary()) ::
          list(Keystore.t())
  def decode_validator_keystores(keystore_dir, keystore_pass_dir)
      when is_binary(keystore_dir) and is_binary(keystore_pass_dir) do
    keystore_dir
    |> File.ls!()
    |> Enum.flat_map(&paths_from_filename(keystore_dir, keystore_pass_dir, &1, Path.extname(&1)))
    |> Enum.flat_map(&decode_key/1)
  end

  defp paths_from_filename(keystore_dir, keystore_pass_dir, filename, ".json") do
    basename = Path.basename(filename, ".json")

    keystore_file = Path.join(keystore_dir, "#{basename}.json")
    keystore_pass_file = Path.join(keystore_pass_dir, "#{basename}.txt")

    [{keystore_file, keystore_pass_file}]
  end

  defp paths_from_filename(_keystore_dir, _keystore_pass_dir, basename, _ext) do
    Logger.warning("[Validator] Skipping file: #{basename}. Not a json keystore file.")
    []
  end

  defp decode_key({keystore_file, keystore_pass_file}) do
    # TODO: remove `try` and handle errors properly
    [Keystore.decode_from_files!(keystore_file, keystore_pass_file)]
  rescue
    error ->
      Logger.error(
        "[Validator] Failed to decode keystore file: #{keystore_file}. Pass file: #{keystore_pass_file} Error: #{inspect(error)}"
      )

      []
  end
end
