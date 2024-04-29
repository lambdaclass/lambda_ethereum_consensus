defmodule CustomConfig do
  @moduledoc """
  Custom, dynamically-loaded config constants.
  """
  alias ChainSpec.GenConfig
  @behaviour GenConfig

  def load_from_file!(path) do
    config = ConfigUtils.load_config_from_file!(path)
    preset = Map.fetch!(config, "PRESET_BASE") |> ConfigUtils.parse_preset()
    config_name = Map.get(config, "CONFIG_NAME") |> ConfigUtils.parse_config()

    merged_config =
      preset.get_preset()
      |> Map.merge(get_base_config(config_name))
      |> Map.merge(config)

    Application.put_env(:lambda_ethereum_consensus, __MODULE__, merged: merged_config)
  end

  @impl GenConfig
  def get_all() do
    Application.get_env(:lambda_ethereum_consensus, __MODULE__)
    |> Keyword.fetch!(:merged)
    |> Map.new(fn {k, v} -> {k, parse_int(v)} end)
  end

  @impl GenConfig
  def get(key), do: get_all() |> Map.fetch!(key)

  # Parses as integer if parsable. If not, returns original value.
  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} -> i
      _ -> v
    end
  end

  defp parse_int(v), do: v

  defp get_base_config(:unknown), do: %{}
  defp get_base_config(config_name), do: config_name.get_all()
end
