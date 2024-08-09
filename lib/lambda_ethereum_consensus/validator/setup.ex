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

    %{}
  end

  defp setup_validators(slot, head_root, keystore_dir, keystore_pass_dir) do
    validator_keystores = decode_validator_keystores(keystore_dir, keystore_pass_dir)

    validators =
      validator_keystores
      |> Enum.map(fn keystore ->
        {keystore.pubkey, Validator.new({slot, head_root, keystore})}
      end)
      |> Map.new()

    Logger.info("[Validator] Initialized #{Enum.count(validators)} validators")

    validators
  end

  @doc """
    Get validator keystores from the keystore directory.
    This function expects two files for each validator:
      - <keystore_dir>/<public_key>.json
      - <keystore_pass_dir>/<public_key>.txt
  """
  @spec decode_validator_keystores(binary(), binary()) ::
          list({Bls.pubkey(), Bls.privkey()})
  def decode_validator_keystores(keystore_dir, keystore_pass_dir)
      when is_binary(keystore_dir) and is_binary(keystore_pass_dir) do
    File.ls!(keystore_dir)
    |> Enum.map(fn filename ->
      if String.ends_with?(filename, ".json") do
        base_name = String.trim_trailing(filename, ".json")

        keystore_file = Path.join(keystore_dir, "#{base_name}.json")
        keystore_pass_file = Path.join(keystore_pass_dir, "#{base_name}.txt")

        {keystore_file, keystore_pass_file}
      else
        Logger.warning("[Validator] Skipping file: #{filename}. Not a keystore file.")
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn {keystore_file, keystore_pass_file} ->
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
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec notify_validators(map(), tuple()) :: map()
  def notify_validators(validators, msg) do
    start_time = System.monotonic_time(:millisecond)

    Logger.debug("[Validator] Notifying all Validators with message: #{inspect(msg)}")

    updated_validators = Map.new(validators, &notify_validator(&1, msg))

    end_time = System.monotonic_time(:millisecond)

    Logger.debug(
      "[Validator] #{inspect(msg)} notified to all Validators after #{end_time - start_time} ms"
    )

    updated_validators
  end

  defp notify_validator({pubkey, validator}, {:on_tick, slot_data}),
    do: {pubkey, Validator.handle_tick(slot_data, validator)}

  defp notify_validator({pubkey, validator}, {:new_head, slot, head_root}),
    do: {pubkey, Validator.handle_new_head(slot, head_root, validator)}
end
