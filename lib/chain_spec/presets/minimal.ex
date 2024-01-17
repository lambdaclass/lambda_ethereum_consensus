defmodule MinimalPreset do
  @moduledoc """
  Minimal preset constants.
  """

  file = "config/presets/minimal"
  @external_resource file

  @parsed_preset ConfigUtils.load_preset_from_dir!(file)

  def get_preset, do: @parsed_preset
end
