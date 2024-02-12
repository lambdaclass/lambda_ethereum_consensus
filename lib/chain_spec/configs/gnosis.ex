defmodule GnosisConfig do
  @moduledoc """
  Gnosis config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/gnosis/config.yaml"
end
