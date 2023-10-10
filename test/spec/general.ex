defmodule GeneralSpecTest do
  @moduledoc """
  "general" config spec tests
  """
  use ExUnit.Case, async: true
  require SpecTestGenerator

  SpecTestGenerator.generate_tests("general")
end
