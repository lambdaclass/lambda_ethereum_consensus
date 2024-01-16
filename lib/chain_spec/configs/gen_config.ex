defmodule ChainSpec.GenConfig do
  @moduledoc """
  Config behaviour, for auto-implementing configs.
  """

  defmacro __using__(opts) do
    file = Keyword.fetch!(opts, :file)
    preset = Keyword.fetch!(opts, :preset)

    quote do
      @external_resource unquote(file)
      @__parsed_config ConfigUtils.load_config_from_file!(unquote(file))
      @__unified Map.merge(unquote(preset).get_preset(), @__parsed_config)

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
