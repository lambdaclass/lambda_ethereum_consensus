defmodule MinimalCapellaSpecTest do
  @moduledoc """
  "minimal" config spec tests for the "capella" fork
  """
  require SpecTestGenerator

  # NOTE: we only support capella for now
  SpecTestGenerator.generate_tests("minimal", "capella")
end
