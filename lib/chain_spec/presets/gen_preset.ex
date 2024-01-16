defmodule ChainSpec.GenPreset do
  @moduledoc """
  Generic preset behaviour, for auto-implementing presets.
  """

  defmacro __using__(opts) do
    file = Keyword.fetch!(opts, :file)

    quote do
      @external_resource unquote(file)

      @__parsed_preset ConfigUtils.load_preset_from_dir!(unquote(file))

      @behaviour unquote(__MODULE__)

      @impl unquote(__MODULE__)
      def get_preset, do: @__parsed_preset
    end
  end

  @doc """
  Fetches the whole preset.
  """
  @callback get_preset() :: map()
end
