defmodule MinimalConfig do
  @moduledoc """
  Minimal config constants.
  """

  @parsed_config ConfigUtils.load_config_from_file!("config/networks/minimal/config.yaml")
  @unified Map.merge(MinimalPreset.get_preset(), @parsed_config)

  def get(key), do: Map.fetch!(@unified, key)
end
