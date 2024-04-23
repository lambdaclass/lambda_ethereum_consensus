defmodule HoleskyConfig do
  @moduledoc """
  Holešky config constants.
  """
  use ChainSpec.GenConfig, file: "config/networks/holesky/config.yaml"

  genesis_validators_root =
    Base.decode16!("9143AA7C615A7F7115E2B6AAC319C03529DF8242AE705FBA9DF39B79C59FA8B1")

  def genesis_validators_root(), do: unquote(genesis_validators_root)
end
