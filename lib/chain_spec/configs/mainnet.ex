defmodule MainnetConfig do
  @moduledoc """
  Mainnet config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/mainnet/config.yaml"

  genesis_validators_root =
    Base.decode16!("4B363DB94E286120D76EB905340FDD4E54BFE9F06BF33FF6CF5AD27F511BFE95")

  def genesis_validators_root(), do: unquote(genesis_validators_root)
end
