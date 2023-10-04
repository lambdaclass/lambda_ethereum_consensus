defmodule ChainSpec do
  @moduledoc """
  Single entrypoint for fetching chain-specific constants.
  """

  # NOTE: this only works for Capella
  def get(name) do
    config = Application.get_env(__MODULE__, :config, MainnetConfig)
    config.get(name)
  end
end
