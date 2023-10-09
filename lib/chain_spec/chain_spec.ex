defmodule ChainSpec do
  @moduledoc """
  Single entrypoint for fetching chain-specific constants.
  """

  # NOTE: this only works for Capella
  @doc """
  Get value for a specific config / spec
  """
  def get(name) do
    config = Application.get_env(__MODULE__, :config, MainnetConfig)
    config.get(name)
  end

  @doc """
  Get current config being used
  """
  def get_config(), do: Application.get_env(__MODULE__, :config, MainnetConfig)
end
