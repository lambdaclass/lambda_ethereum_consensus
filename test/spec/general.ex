defmodule GeneralSpecTest do
  @moduledoc """
  "general" config spec tests
  """
  use ExUnit.Case, async: true
  require SpecTestUtils

  SpecTestUtils.generate_tests("general")
end
