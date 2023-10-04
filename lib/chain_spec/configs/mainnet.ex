defmodule MainnetConfig do
  @moduledoc """
  Mainnet config constants.
  """

  @parsed_config ConfigUtils.load_config_from_file!("config/configs/mainnet.yaml")
  @unified Map.merge(MainnetPreset.get_preset(), @parsed_config)

  def get(key), do: Map.get(@unified, key)
end
