defmodule MainnetConfig do
  @moduledoc """
  Mainnet config constants.
  """
  file = "config/networks/mainnet/config.yaml"

  @external_resource file

  @parsed_config ConfigUtils.load_config_from_file!(file)
  @unified Map.merge(MainnetPreset.get_preset(), @parsed_config)

  def get(key), do: Map.fetch!(@unified, key)
end
