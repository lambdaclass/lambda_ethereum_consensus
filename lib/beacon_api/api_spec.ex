defmodule BeaconApi.ApiSpec do
  @moduledoc false
  alias OpenApiSpex.OpenApi
  @behaviour OpenApi

  @ethspec "beacon-node-oapi.json"
           |> File.read!()
           |> Jason.decode!()
           |> OpenApiSpex.OpenApi.Decode.decode()

  @impl OpenApi
  def spec, do: @ethspec
end
