defmodule Unit.MinimalConfigSmokeTest do
  use ExUnit.Case

  setup_all do
    Application.put_env(:lambda_ethereum_consensus, ChainSpec, config: MinimalConfig)
  end

  test "in minimal, SLOTS_PER_EPOCH == 8" do
    # Chosen because it's unlikely to change
    assert ChainSpec.get("SLOTS_PER_EPOCH") == 8
  end
end
