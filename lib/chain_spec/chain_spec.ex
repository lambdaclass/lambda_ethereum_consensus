defmodule ChainSpec do
  @moduledoc """
  Single entrypoint for fetching chain-specific constants.
  """

  def get_config(),
    do: Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__) |> Keyword.fetch!(:config)

  def get_preset(), do: get_config().get("PRESET_BASE") |> String.to_atom()

  def get_fork_version_for_epoch(epoch) do
    if epoch >= get("ELECTRA_FORK_EPOCH") do
      get("ELECTRA_FORK_VERSION")
    else
      raise "Forks before Electra are not supported"
    end
  end

  # NOTE: this only works correctly for Capella
  def get(name), do: get_config().get(name)

  def get_all(), do: get_config().get_all()

  def get_genesis_validators_root() do
    Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)
    |> Keyword.fetch!(:genesis_validators_root)
  end
end
