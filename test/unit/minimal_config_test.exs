defmodule Unit.MinimalConfigSmokeTest do
  use ExUnit.Case

  setup_all do
    Application.put_env(Constants, :config, MinimalConfig)
  end

  test "in minimal, SLOTS_PER_EPOCH == 8" do
    # Chosen because it's unlikely to change
    assert Constants.get("SLOTS_PER_EPOCH") == 8
  end
end
