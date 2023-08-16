defmodule MainnetSpecTest do
  @moduledoc """
  "mainnet" config spec tests
  """
  use ExUnit.Case, async: true
  require SpecTestUtils

  SpecTestUtils.generate_tests("mainnet")
end
