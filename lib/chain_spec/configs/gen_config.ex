defmodule ChainSpec.GenConfig do
  @moduledoc """
  Generic config behaviour, for auto-implementing configs.
  """

  defmacro __using__(opts) do
    file = Keyword.fetch!(opts, :file)
    preset = Keyword.fetch!(opts, :preset)

    quote do
      file = unquote(file)
      preset = unquote(preset)

      @external_resource file
      @__parsed_config ConfigUtils.load_config_from_file!(file)
      @__unified Map.merge(preset.get_preset(), @__parsed_config)

      @behaviour unquote(__MODULE__)

      @impl unquote(__MODULE__)
      def get(key), do: Map.fetch!(@__unified, key)
    end
  end

  @doc """
  Fetches a value from config.
  """
  @callback get(String.t()) :: term()
end
