defmodule LambdaEthereumConsensus.Validator.ValidatorManager do
  @moduledoc """
  Module that manage the validators state
  """
  use GenServer

  require Logger
  alias LambdaEthereumConsensus.Beacon.Clock
  alias LambdaEthereumConsensus.Validator

  @spec start_link({Types.slot(), Types.root()}) :: :ignore | {:error, any} | {:ok, pid}
  def start_link({slot, head_root}) do
    GenServer.start_link(__MODULE__, {slot, head_root}, name: __MODULE__)
  end

  @spec init({Types.slot(), Types.root()}) ::
          {:ok, %{Bls.pubkey() => Validator.state()}} | {:stop, any}
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

    Logger.info("[Validator Manager] Initialized #{Enum.count(validators)} validators")

    {:ok, validators}
  end

  @spec notify_new_block(Types.slot(), Types.root()) :: :ok
  def notify_new_block(slot, head_root) do
    # Making this alone a cast solves the issue
    GenServer.cast(__MODULE__, {:notify_all, {:new_block, slot, head_root}})
    # notify_validators({:new_block, slot, head_root})
  end

  @spec notify_tick(Clock.logical_time()) :: :ok
  def notify_tick(logical_time) do
    # Making this a cast alone doesn't solve the issue
    # GenServer.cast(__MODULE__, {:notify_all, {:on_tick, logical_time}})
    notify_validators({:on_tick, logical_time})
  end

  # TODO: The use of a Genserver and cast is still needed to avoid locking at the clock level.
  # This is a temporary solution and will be taken off in a future PR.
  defp notify_validators(msg), do: GenServer.call(__MODULE__, {:notify_all, msg})

  def handle_cast({:notify_all, msg}, validators) do
    validators = notify_all(validators, msg)

    {:noreply, validators}
  end

  def handle_call({:notify_all, msg}, _from, validators) do
    validators = notify_all(validators, msg)

    {:reply, :ok, validators}
  end

  defp notify_all(validators, msg) do
    start_time = System.monotonic_time(:millisecond)

    updated_validators = Enum.map(validators, &notify_validator(&1, msg))

    end_time = System.monotonic_time(:millisecond)

    Logger.debug(
      "[Validator Manager] #{inspect(msg)} notified to all Validators after #{end_time - start_time} ms"
    )

    updated_validators
  end

  defp notify_validator({pubkey, validator}, {:on_tick, logical_time}),
    do: {pubkey, Validator.handle_tick(logical_time, validator)}

  defp notify_validator({pubkey, validator}, {:new_block, slot, head_root}),
    do: {pubkey, Validator.handle_new_block(slot, head_root, validator)}

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
