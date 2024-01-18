defmodule MainnetPreset do
  @moduledoc """
  Mainnet preset constants.
  """

  file = "config/presets/mainnet"
  @external_resource file

  @parsed_preset ConfigUtils.load_preset_from_dir!(file)

  def get_preset, do: @parsed_preset
end
