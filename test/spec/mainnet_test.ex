defmodule MainnetSpecTest do
  use ExUnit.Case, async: true
  require SpecTestUtils

  SpecTestUtils.generate_tests("mainnet")
end
