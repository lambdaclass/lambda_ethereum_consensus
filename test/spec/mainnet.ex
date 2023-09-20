defmodule MainnetSpecTest do
  @moduledoc """
  "mainnet" config spec tests
  """
  use ExUnit.Case, async: true
  require SpecTestGenerator

  # NOTE: we only support capella for now
  SpecTestGenerator.generate_tests("mainnet", "capella")
end
