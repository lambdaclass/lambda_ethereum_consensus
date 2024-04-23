defmodule SepoliaConfig do
  @moduledoc """
  Sepolia config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/sepolia/config.yaml"

  genesis_validators_root =
    Base.decode16!("D8EA171F3C94AEA21EBC42A1ED61052ACF3F9209C00E4EFBAADDAC09ED9B8078")

  def genesis_validators_root(), do: unquote(genesis_validators_root)
end
