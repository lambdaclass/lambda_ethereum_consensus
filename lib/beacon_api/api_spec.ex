defmodule BeaconApi.ApiSpec do
  @moduledoc false
  alias OpenApiSpex.{Info, OpenApi, Paths, Server}
  alias BeaconApi.{Endpoint, Router}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: "LambdaEthereumConsensus",
        version: "0.0.1"
      },
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
