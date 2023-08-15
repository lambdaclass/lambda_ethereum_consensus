defmodule GeneralSpecTest do
  use ExUnit.Case, async: true
  require SpecTestUtils

  SpecTestUtils.generate_tests("general")
end
