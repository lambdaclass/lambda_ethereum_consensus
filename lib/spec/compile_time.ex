defmodule SpecTestCompileUtils do
  @moduledoc """
  Compile time utilities for spec tests.
  """

  def get_vectors_dir, do: "test/spec/vectors/tests"

  def get_config("minimal"), do: MinimalConfig
  def get_config("mainnet"), do: MainnetConfig
  def get_config("general"), do: MainnetConfig
end
