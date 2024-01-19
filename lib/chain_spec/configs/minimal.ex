defmodule MinimalConfig do
  @moduledoc """
  Minimal config constants.
  """
  file = "config/networks/minimal/config.yaml"

  @external_resource file

  @parsed_config ConfigUtils.load_config_from_file!(file)
  @unified Map.merge(MinimalPreset.get_preset(), @parsed_config)

  def get(key), do: Map.fetch!(@unified, key)
end
