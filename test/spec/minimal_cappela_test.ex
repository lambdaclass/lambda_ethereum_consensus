defmodule MinimalCapellaSpecTest do
  use ExUnit.Case, async: true
  require SpecTestUtils

  SpecTestUtils.generate_tests("minimal", "capella")
end
