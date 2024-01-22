defmodule SepoliaConfig do
  @moduledoc """
  Sepolia config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/sepolia/config.yaml"
end
