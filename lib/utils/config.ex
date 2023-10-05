defmodule ConfigUtils do
  @moduledoc """
  Utilities for parsing configs and presets.
  """
  @forks ["phase0", "altair", "bellatrix", "capella"]

  def load_config_from_file!(path), do: YamlElixir.read_from_file!(path)

  def load_preset_from_dir!(path) do
    # TODO: we should return the merged preset for each fork here
    @forks
    |> Stream.map(&Path.join([path, "#{&1}.yaml"]))
    |> Stream.map(&YamlElixir.read_from_file!/1)
    # The order is to ensure that the later forks override the earlier ones.
    |> Enum.reduce(&Map.merge(&2, &1))
  end
end
