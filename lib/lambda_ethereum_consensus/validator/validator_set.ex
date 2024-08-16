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

    setup_validators(slot, head_root, keystore_dir, keystore_pass_dir)
  end

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

    validators =
      Map.new(validator_keystores, fn keystore ->
        validator = Validator.new(keystore, slot, head_root)
        {validator.index, validator}
      end)

    Logger.info("[Validator] Initialized #{Enum.count(validators)} validators")

    %__MODULE__{validators: validators}
    |> update_state(epoch, slot, head_root)
  end

  @doc """
  Notify all validators of a new head.
  """
  @spec notify_head(t(), Types.slot(), Types.root()) :: t()
  def notify_head(set, slot, head_root) do
    Logger.debug("[ValidatorSet] New Head", root: head_root, slot: slot)
    epoch = Misc.compute_epoch_at_slot(slot)

    set
    |> update_state(epoch, slot, head_root)
    |> attests(epoch, slot, head_root)
    |> build_payload(slot + 1, head_root)
  end

  @doc """
  Notify all validators of a new tick.
  """
  @spec notify_tick(t(), tuple()) :: t()
  def notify_tick(%{head_root: head_root} = set, {slot, third} = slot_data) do
    Logger.debug("[ValidatorSet] Tick #{inspect(third)}", root: head_root, slot: slot)
    epoch = Misc.compute_epoch_at_slot(slot)

    set
    |> update_state(epoch, slot, head_root)
    |> process_tick(epoch, slot_data)
  end

  defp process_tick(%{head_root: head_root} = set, epoch, {slot, :first_third}) do
    propose(set, epoch, slot, head_root)
  end

  defp process_tick(%{head_root: head_root} = set, epoch, {slot, :second_third}) do
    set
    |> attests(epoch, slot, head_root)
    |> build_payload(slot + 1, head_root)
  end

  defp process_tick(set, epoch, {slot, :last_third}) do
    publish_aggregates(set, epoch, slot)
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
       when is_duties_computed(set, epoch) and is_duties_computed(set, epoch + 1),
       do: set

  defp compute_duties(set, epoch, slot, head_root) do
    epochs_to_calculate =
      [{epoch, slot}, {epoch + 1, Misc.compute_start_slot_at_epoch(epoch + 1)}]
      |> Enum.reject(&Map.has_key?(set.duties, elem(&1, 0)))

    epochs_to_calculate
    |> Map.new(&compute_duties_for_epoch!(set, &1, head_root))
    |> merge_duties_and_prune(epoch, set)
  end

  defp compute_duties_for_epoch!(set, {epoch, slot}, head_root) do
    beacon = Validator.fetch_target_state_and_go_to_slot(epoch, slot, head_root)

    duties = %{
      proposers: Duties.compute_proposers_for_epoch(beacon, epoch, set.validators),
      attesters: Duties.compute_attesters_for_epoch(beacon, epoch, set.validators)
    }

    Duties.log_duties_for_epoch(duties, epoch)

    {epoch, duties}
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

  defp build_payload(%{validators: validators} = set, slot, head_root) do
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

  defp propose(%{validators: validators} = set, epoch, slot, head_root) do
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
  # Attestation

  defp attests(set, epoch, slot, head_root) do
    case Duties.current_attesters(set.duties, epoch, slot) do
      [] ->
        set

      attester_duties ->
        attester_duties
        |> Enum.map(&attest(&1, slot, head_root, set.validators))
        |> update_duties(set, epoch, :attesters, slot)
    end
  end

  defp publish_aggregates(set, epoch, slot) do
    case Duties.current_aggregators(set.duties, epoch, slot) do
      [] ->
        set

      aggregator_duties ->
        aggregator_duties
        |> Enum.map(&publish_aggregate(&1, slot, set.validators))
        |> update_duties(set, epoch, :attesters, slot)
    end
  end

  defp attest(duty, slot, head_root, validators) do
    validators
    |> Map.get(duty.validator_index)
    |> Validator.attest(duty, slot, head_root)

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

  ##############################
  # Key management

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
