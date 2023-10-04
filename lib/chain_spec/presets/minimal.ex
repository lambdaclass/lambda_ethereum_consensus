defmodule MinimalPreset do
  @moduledoc """
  Minimal preset constants.
  """

  @parsed_preset ConfigUtils.load_preset_from_dir!("config/presets/minimal")

  def get_preset, do: @parsed_preset
end
