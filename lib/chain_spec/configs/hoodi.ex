defmodule HoodiConfig do
  @moduledoc """
  Hoodi config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/hoodi/config.yaml"

  genesis_validators_root =
    Base.decode16!("212F13FC4DF078B6CB7DB228F1C8307566DCECF900867401A92023D7BA99CB5F")

  def genesis_validators_root(), do: unquote(genesis_validators_root)
end
