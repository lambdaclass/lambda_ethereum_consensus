defmodule MinimalCapellaSpecTest do
  @moduledoc """
  "minimal" config spec tests for the "capella" fork
  """
  use ExUnit.Case, async: true
  require SpecTestGenerator

  setup_all do
    Application.put_env(ChainSpec, :config, MinimalConfig)
  end

  # NOTE: we only support capella for now
  SpecTestGenerator.generate_tests("minimal", "capella")
end
