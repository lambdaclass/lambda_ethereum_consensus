defmodule MainnetSpecTest do
  @moduledoc """
  "mainnet" config spec tests
  """
  use ExUnit.Case, async: true
  require SpecTestGenerator

  SpecTestGenerator.generate_tests("mainnet")
end
