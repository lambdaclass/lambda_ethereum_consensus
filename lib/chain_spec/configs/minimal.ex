defmodule MinimalConfig do
  @moduledoc """
  Minimal config constants. These are used only for tests.
  """
  use ChainSpec.GenConfig, file: "config/networks/minimal/config.yaml"

  def genesis_validators_root(), do: <<0::256>>
end
