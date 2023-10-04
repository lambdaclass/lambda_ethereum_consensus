defmodule MainnetSpecTest do
  @moduledoc """
  "mainnet" config spec tests
  """
  use ExUnit.Case, async: true
  require SpecTestGenerator

  setup_all do
    Application.put_env(Constants, :config, MainnetConfig)
  end

  # NOTE: we only support capella for now
  SpecTestGenerator.generate_tests("mainnet", "capella")
end
