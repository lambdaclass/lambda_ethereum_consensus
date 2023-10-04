defmodule GeneralSpecTest do
  @moduledoc """
  "general" config spec tests
  """
  use ExUnit.Case, async: true
  require SpecTestGenerator

  setup_all do
    Application.put_env(ChainSpec, :config, MainnetConfig)
  end

  SpecTestGenerator.generate_tests("general")
end
