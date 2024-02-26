defmodule CustomConfig do
  @moduledoc """
  Custom, dynamically-loaded config constants.
  """
  alias ChainSpec.GenConfig
  @behaviour GenConfig

  def load_config(path) do
    config = Path.join(path, "config.yaml") |> ConfigUtils.load_config_from_file!()
    preset = Map.fetch!(config, "PRESET_BASE") |> GenConfig.parse_preset()
    merged_config = Map.merge(preset.get_preset(), config)
    Application.put_env(:lambda_ethereum_consensus, __MODULE__, merged: merged_config)
  end

  defp get_config,
    do: Application.get_env(:lambda_ethereum_consensus, __MODULE__) |> Keyword.fetch!(:merged)

  @impl GenConfig
  def get(key), do: get_config() |> Map.fetch!(key)
end
