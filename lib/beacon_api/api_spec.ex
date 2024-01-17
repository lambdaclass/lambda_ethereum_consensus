defmodule BeaconApi.ApiSpec do
  @moduledoc false
  alias OpenApiSpex.OpenApi
  @behaviour OpenApi

  file = "beacon-node-oapi.json"
  @external_resource file
  @ethspec file
           |> File.read!()
           |> Jason.decode!()
           |> OpenApiSpex.OpenApi.Decode.decode()

  @impl OpenApi
  def spec, do: @ethspec
end
