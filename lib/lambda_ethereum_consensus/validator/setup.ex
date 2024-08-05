defmodule LambdaEthereumConsensus.Validator.Setup do
  @moduledoc """
  Module that setups the initial validators state
  """

  require Logger
  alias LambdaEthereumConsensus.Validator

  @spec init(Types.slot(), Types.root()) :: %{Bls.pubkey() => Validator.state()}
  def init(slot, head_root) do
    config = Application.get_env(:lambda_ethereum_consensus, __MODULE__, [])
    keystore_dir = Keyword.get(config, :keystore_dir)
    keystore_pass_dir = Keyword.get(config, :keystore_pass_dir)

    setup_validators(slot, head_root, keystore_dir, keystore_pass_dir)
  end

  defp setup_validators(_s, _r, keystore_dir, keystore_pass_dir)
       when is_nil(keystore_dir) or is_nil(keystore_pass_dir) do
    Logger.warning(
      "[Validator] No keystore_dir or keystore_pass_dir provided. Validator will not start."
    )

    []
  end

  defp setup_validators(slot, head_root, keystore_dir, keystore_pass_dir) do
    validator_keys = decode_validator_keys(keystore_dir, keystore_pass_dir)

    validators = Enum.map(validator_keys, &Validator.new({slot, head_root, &1}))

    Logger.info("[Validator] Initialized #{Enum.count(validators)} validators")

    validators
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
    |> map_rejecting_nils(
      &paths_from_filename(keystore_dir, keystore_pass_dir, &1, Path.extname(&1))
    )
    |> map_rejecting_nils(&decode_key/1)
  end

  defp decode_key({keystore_file, keystore_pass_file}) do
    # TODO: remove `try` and handle errors properly
    try do
      Keystore.decode_from_files!(keystore_file, keystore_pass_file)
    rescue
      error ->
        Logger.error(
          "[Validator] Failed to decode keystore file: #{keystore_file}. Pass file: #{keystore_pass_file} Error: #{inspect(error)}"
        )

        nil
    end
  end

  defp paths_from_filename(keystore_dir, keystore_pass_dir, filename, ".json") do
    basename = Path.basename(filename, ".json")

    keystore_file = Path.join(keystore_dir, "#{basename}.json")
    keystore_pass_file = Path.join(keystore_pass_dir, "#{basename}.txt")

    {keystore_file, keystore_pass_file}
  end

  defp paths_from_filename(_keystore_dir, _keystore_pass_dir, basename, _ext) do
    Logger.warning("[Validator] Skipping file: #{basename}. Not a json keystore file.")
    nil
  end

  @spec notify_validators([Validator.state()], tuple()) :: [Validator.state()]
  def notify_validators(validators, msg) do
    start_time = System.monotonic_time(:millisecond)

    Logger.debug("[Validator] Notifying all Validators with message: #{inspect(msg)}")

    updated_validators = Enum.map(validators, &notify_validator(&1, msg))

    end_time = System.monotonic_time(:millisecond)

    Logger.debug(
      "[Validator] #{inspect(msg)} notified to all Validators after #{end_time - start_time} ms"
    )

    updated_validators
  end

  defp notify_validator(validator, {:on_tick, slot_data}),
    do: Validator.handle_tick(slot_data, validator)

  defp notify_validator(validator, {:new_head, slot, head_root}),
    do: Validator.handle_new_head(slot, head_root, validator)

  defp map_rejecting_nils(enumerable, fun) do
    Enum.reduce(enumerable, [], fn elem, acc ->
      case fun.(elem) do
        nil -> acc
        result -> [result | acc]
      end
    end)
  end
end
