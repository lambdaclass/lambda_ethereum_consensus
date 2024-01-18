defmodule MainnetConfig do
  @moduledoc """
  Mainnet config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/mainnet/config.yaml"
end
