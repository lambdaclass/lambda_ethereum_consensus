defmodule ChainSpec do
  @moduledoc """
  Single entrypoint for fetching chain-specific constants.
  """

  def get_config, do: Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)[:config]

  def get_fork_version_for_epoch(epoch) do
    capella_version = get("CAPELLA_FORK_VERSION")
    cappella_epoch = get("CAPELLA_FORK_EPOCH")

    if epoch >= cappella_epoch do
      capella_version
    else
      raise "Forks before Capella are not supported"
    end
  end

  # NOTE: this only works correctly for Capella
  def get(name), do: get_config().get(name)
end
