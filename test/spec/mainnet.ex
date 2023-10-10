defmodule MainnetSpecTest do
  @moduledoc """
  "mainnet" config spec tests
  """
  require SpecTestGenerator

  # NOTE: we only support capella for now
  SpecTestGenerator.generate_tests("mainnet", "capella")
end
