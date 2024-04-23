defmodule GnosisConfig do
  @moduledoc """
  Gnosis config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/gnosis/config.yaml"

  genesis_validators_root =
    Base.decode16!("F5DCB5564E829AAB27264B9BECD5DFAA017085611224CB3036F573368DBB9D47")

  def genesis_validators_root(), do: unquote(genesis_validators_root)
end
