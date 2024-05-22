defmodule LambdaEthereumConsensus.Validator.ValidatorManager do
  @moduledoc false

  use Supervisor

  require Logger
  alias LambdaEthereumConsensus.Validator

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init({slot, head_root}) do
    config = Application.get_env(:lambda_ethereum_consensus, __MODULE__, [])

    keystore_dir = Keyword.get(config, :keystore_dir)
    keystore_pass_dir = Keyword.get(config, :keystore_pass_dir)
    validator_keys = decode_validator_keys(keystore_dir, keystore_pass_dir)

    children =
      validator_keys
      |> Enum.map(fn {pubkey, privkey} ->
        Supervisor.child_spec({Validator, {slot, head_root, {pubkey, privkey}}},
          id: pubkey
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end

  def notify_new_block(slot, head_root) do
    cast_to_children({:new_block, slot, head_root})
  end

  def notify_tick(logical_time) do
    cast_to_children({:on_tick, logical_time})
  end

  defp cast_to_children(msg) do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} -> GenServer.cast(pid, msg) end)
  end

  @doc """
    Get validator keys from the keystore directory.
    This function expects two files for each validator:
      - <keystore_dir>/<public_key>.json
      - <keystore_pass_dir>/<public_key>.txt
  """
  @spec decode_validator_keys(binary(), binary()) :: list({Bls.pubkey(), Bls.privkey()})
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
