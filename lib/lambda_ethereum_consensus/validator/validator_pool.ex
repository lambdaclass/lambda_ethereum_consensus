defmodule LambdaEthereumConsensus.ValidatorSet do
  @moduledoc """
  Module that holds the set of validators and their states,
  it also manages the validator's duties as bitmaps to
  simplify the delegation of work.
  """

  defstruct epoch: nil, slot: nil, head_root: nil, validators: %{uninitialized: []}

  require Logger

  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.Store.CheckpointStates
  alias LambdaEthereumConsensus.Validator
  alias LambdaEthereumConsensus.Validator.Duties

  @type validators :: %{atom() => %{} | []}
  @type t :: %__MODULE__{
          epoch: Types.epoch() | nil,
          slot: Types.slot() | nil,
          head_root: Types.root() | nil,
          validators: validators()
        }

  @doc """
  Initiate the pool of validators, given the slot and head root.
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
    validator_keys = decode_validator_keys(keystore_dir, keystore_pass_dir)

    epoch = Misc.compute_epoch_at_slot(slot)
    beacon = fetch_target_state!(epoch, head_root)

    validators = Map.new(validator_keys, fn validator_key ->
      validator = Validator.new(validator_key, epoch, slot, head_root, beacon)
      {validator.validator.index, validator}
    end)

    Logger.info("[Validator] Initialized #{Enum.count(validators)} validators")

    proposers = Duties.compute_proposers_for_epoch(beacon, epoch, validators)

    %__MODULE__{
      epoch: epoch,
      slot: slot,
      head_root: head_root,
      validators: %{
        proposers: proposers,
        uninitialized: validators}
    }
  end

  defp fetch_target_state!(epoch, head_root) do
    {:ok, state} = CheckpointStates.compute_target_checkpoint_state(epoch, head_root)
    state
  end

  @doc """
  Notify all validators of a new head.
  """
  @spec notify_head(t(), Types.slot(), Types.root()) :: t()
  def notify_head(%{validators: %{uninitialized: validators}} = pool, slot, head_root) do
    uninitialized_validators =
      maybe_debug_notify(
        fn ->
          Map.new(validators, fn {k, v} ->
            {k, Validator.handle_new_head(slot, head_root, v)}
          end)
        end,
        {:new_head, slot, head_root}
      )

    %{pool | validators: %{uninitialized: uninitialized_validators}}
  end

  @doc """
  Notify all validators of a new tick.
  """
  @spec notify_tick(t(), tuple()) :: t()
  def notify_tick(%{validators: %{uninitialized: validators}} = pool, slot_data) do
    uninitialized_validators =
      maybe_debug_notify(
        fn ->
          Map.new(validators,  fn {k, v} ->
            {k, Validator.handle_tick(slot_data, v)}
          end)
        end,
        {:on_tick, slot_data}
      )

    %{pool | validators: %{uninitialized: uninitialized_validators}}
  end

  defp maybe_debug_notify(fun, data) do
    if Application.get_env(:logger, :level) == :debug do
      Logger.debug("[Validator] Notifying all Validators with message: #{inspect(data)}")

      start_time = System.monotonic_time(:millisecond)
      result = fun.()
      end_time = System.monotonic_time(:millisecond)

      Logger.debug(
        "[Validator] #{inspect(data)} notified to all Validators after #{end_time - start_time} ms"
      )

      result
    else
      fun.()
    end
  end

  @doc """
    Get validator keys from the keystore directory.
    This function expects two files for each validator:
      - <keystore_dir>/<public_key>.json
      - <keystore_pass_dir>/<public_key>.txt
  """
  @spec decode_validator_keys(binary(), binary()) ::
          list({Bls.pubkey(), Bls.privkey()})
  def decode_validator_keys(keystore_dir, keystore_pass_dir)
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
