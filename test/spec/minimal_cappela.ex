defmodule MinimalCapellaSpecTest do
  @moduledoc """
  "minimal" config spec tests for the "capella" fork
  """
  use ExUnit.Case, async: true
  require SpecTestUtils

  SpecTestUtils.generate_tests("minimal", "capella")
end
