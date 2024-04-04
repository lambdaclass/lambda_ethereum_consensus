defmodule Unit.MainnetConfigSmokeTest do
  use ExUnit.Case

  doctest HardForkAliasInjection

  setup_all do
    Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
    |> Keyword.put(:config, MainnetConfig)
    |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
  end

  test "in mainnet, SLOTS_PER_EPOCH == 32" do
    # Chosen because it's unlikely to change
    assert ChainSpec.get("SLOTS_PER_EPOCH") == 32
  end
end
