defmodule SepoliaConfig do
  @moduledoc """
  Sepolia config constants.
  """

  @parsed_config ConfigUtils.load_config_from_file!("config/networks/sepolia/config.yaml")
  @unified Map.merge(MainnetPreset.get_preset(), @parsed_config)

  def get(key), do: Map.fetch!(@unified, key)
end
