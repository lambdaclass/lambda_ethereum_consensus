defmodule MinimalCapellaSpecTest do
  @moduledoc """
  "minimal" config spec tests for the "capella" fork
  """
  use ExUnit.Case, async: true
  require SpecTestGenerator

  SpecTestGenerator.generate_tests("minimal", "capella")
end
