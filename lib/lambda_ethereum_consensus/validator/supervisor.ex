defmodule LambdaEthereumConsensus.Validator.Supervisor do
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

    if keystore_dir == nil or keystore_pass_dir == nil do
      Logger.warning(
        "[Validator] No keystore_dir or keystore_pass_dir provided. Validator will not start."
      )

      :ignore
    else
      validator_keys = get_validator_keys(keystore_dir, keystore_pass_dir)

      children =
        validator_keys
        |> Enum.map(fn {pubkey, privkey} ->
          Supervisor.child_spec({Validator, {slot, head_root, {pubkey, privkey}}},
            id: pubkey |> Base.encode16(case: :lower) |> String.to_atom()
          )
        end)

      Supervisor.init(children, strategy: :one_for_one)
    end
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

  @spec get_validator_keys(binary(), binary()) :: list({Bls.pubkey(), Bls.privkey()})
  defp get_validator_keys(keystore_dir, keystore_pass_dir) do
    keystore_files = File.ls!(keystore_dir) |> Enum.sort()
    keystore_pass_files = File.ls!(keystore_pass_dir) |> Enum.sort()

    Enum.zip(keystore_files, keystore_pass_files)
    |> Enum.map(fn {keystore_file, keystore_pass_file} ->
      keystore_file = Path.join(keystore_dir, keystore_file)
      keystore_pass_file = Path.join(keystore_pass_dir, keystore_pass_file)

      # TODO: remove `try` and handle errors properly
      # TODO: match keystore file and pass file based on name
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
    |> Enum.filter(&is_tuple/1)
  end
end
