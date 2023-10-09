defmodule ChainSpec do
  @moduledoc """
  Single entrypoint for fetching chain-specific constants.
  """

  def get_config, do: Application.get_env(__MODULE__, :config, MainnetConfig)

  # NOTE: this only works correctly for Capella
  def get(name), do: get_config().get(name)
end
