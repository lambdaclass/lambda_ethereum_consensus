defmodule SepoliaConfig do
  @moduledoc """
  Sepolia config constants.
  """
  file = "config/networks/sepolia/config.yaml"

  @external_resource file

  @parsed_config ConfigUtils.load_config_from_file!(file)
  @unified Map.merge(MainnetPreset.get_preset(), @parsed_config)

  def get(key), do: Map.fetch!(@unified, key)
end
