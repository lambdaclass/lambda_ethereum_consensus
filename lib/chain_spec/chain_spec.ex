defmodule ChainSpec do
  @moduledoc """
  Single entrypoint for fetching chain-specific constants.
  """

  def get_config, do: Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)[:config]

  # NOTE: this only works correctly for Capella
  def get(name), do: get_config().get(name)
end
