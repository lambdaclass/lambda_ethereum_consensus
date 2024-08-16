defmodule KeyStoreApi.ApiSpec do
  @moduledoc false
  alias OpenApiSpex.OpenApi
  @behaviour OpenApi

  file = "keymanager-oapi.yaml"
  @external_resource file
  @ethspec YamlElixir.read_from_file!(file)
           |> OpenApiSpex.OpenApi.Decode.decode()

  @impl OpenApi
  def spec(), do: @ethspec
end
