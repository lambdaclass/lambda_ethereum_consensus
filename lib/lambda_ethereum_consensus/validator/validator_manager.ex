defmodule LambdaEthereumConsensus.Validator.ValidatorManager do
  @moduledoc """
  Module that manage the validators state
  """
  use GenServer

  require Logger
  alias LambdaEthereumConsensus.Validator

  def start_link({slot, head_root}) do
    GenServer.start_link(__MODULE__, {slot, head_root}, name: __MODULE__)
  end

  def init({slot, head_root}) do
    config = Application.get_env(:lambda_ethereum_consensus, __MODULE__, [])
    keystore_dir = Keyword.get(config, :keystore_dir)
    keystore_pass_dir = Keyword.get(config, :keystore_pass_dir)

    setup_validators(slot, head_root, keystore_dir, keystore_pass_dir)
  end

  defp setup_validators(_s, _r, keystore_dir, keystore_pass_dir)
       when is_nil(keystore_dir) or is_nil(keystore_pass_dir) do
    Logger.warning(
      "[Validator Manager] No keystore_dir or keystore_pass_dir provided. Validator will not start."
    )

    {:ok, []}
  end

  defp setup_validators(slot, head_root, keystore_dir, keystore_pass_dir) do
    validator_keys = decode_validator_keys(keystore_dir, keystore_pass_dir)

    validators =
      validator_keys
      |> Enum.map(fn {pubkey, privkey} ->
        {pubkey, Validator.new({slot, head_root, {pubkey, privkey}})}
      end)
      |> Map.new()

    Logger.info("[Validator Manager] Initialized validators #{inspect(Map.keys(validators))}")

    {:ok, validators}
  end

  def notify_new_block(slot, head_root) do
    notify_validators({:new_block, slot, head_root})
  end

  def notify_tick(logical_time) do
    notify_validators({:on_tick, logical_time})
  end

  defp notify_validators(msg) do
    # This is a really naive and blocking implementation. This is just an initial iteration
    # to remove the GenServer behavior in the validators.
    Logger.info("[Validator Manager] Self: #{inspect(self())} Notifying validators: #{inspect(msg)}")

    #Agent.update(__MODULE__, &notify_all(&1, msg), 17_000)
    GenServer.cast(__MODULE__, {:notify_all, msg})
  end

  def handle_cast({:notify_all, msg}, validators) do
    validators = notify_all(validators, msg)

    {:noreply, validators}
  end

  defp notify_all(validators, msg) do
    {time, value} =
      :timer.tc(fn -> Enum.map(validators, &notify_validator(&1, msg)) end)

    Logger.info(
      "[Validator Manager] Self: #{inspect(self())} Validators notified of #{inspect(elem(msg, 0))} after #{time / 1_000}ms"
    )

    value
  end

  defp notify_validator({pubkey, validator}, msg), do: {pubkey, Validator.notify(msg, validator)}

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
    File.ls!(keystore_dir)
    |> Enum.map(fn filename ->
      if String.ends_with?(filename, ".json") do
        base_name = String.trim_trailing(filename, ".json")

        keystore_file = Path.join(keystore_dir, "#{base_name}.json")
        keystore_pass_file = Path.join(keystore_pass_dir, "#{base_name}.txt")

        {keystore_file, keystore_pass_file}
      else
        Logger.warning("[Validator Manager] Skipping file: #{filename}. Not a keystore file.")
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
            "[Validator Manager] Failed to decode keystore file: #{keystore_file}. Pass file: #{keystore_pass_file} Error: #{inspect(error)}"
          )

          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
