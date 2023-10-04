defmodule Unit.MainnetConfigSmokeTest do
  use ExUnit.Case

  setup_all do
    Application.put_env(Constants, :config, MainnetConfig)
  end

  test "in mainnet, SLOTS_PER_EPOCH == 32" do
    # Chosen because it's unlikely to change
    assert Constants.get("SLOTS_PER_EPOCH") == 32
  end
end
