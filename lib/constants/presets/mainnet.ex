defmodule MainnetPreset do
  @moduledoc """
  Mainnet preset constants.
  """

  @parsed_preset ConfigUtils.load_preset_from_dir!("config/presets/mainnet")

  def get_preset, do: @parsed_preset
end
