defmodule MinimalConfig do
  @moduledoc """
  Minimal config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/minimal/config.yaml", preset: MinimalPreset
end
