defmodule Constants do
  @moduledoc """
  Single entrypoint for fetching eth-spec constants.
  """

  # NOTE: this only works for Capella
  def get(name) do
    config = Application.get_env(__MODULE__, :config, MainnetConfig)
    config.get(name)
  end
end
