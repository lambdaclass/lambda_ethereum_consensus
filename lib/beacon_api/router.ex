defmodule BeaconApi.Router do
  use BeaconApi, :router
  require Logger

  pipeline :api do
    plug(:accepts, ["json", "sse"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: BeaconApi.ApiSpec)
    plug(:log_requests)
  end

  # Ethereum API Version 1
  scope "/eth/v1", BeaconApi.V1 do
    pipe_through(:api)

    scope "/beacon" do
      get("/genesis", BeaconController, :get_genesis)
      get("/states/:state_id/root", BeaconController, :get_state_root)
      get("/blocks/:block_id/root", BeaconController, :get_block_root)
      get("/states/:state_id/finality_checkpoints", BeaconController, :get_finality_checkpoints)
      get("/headers/:block_id", BeaconController, :get_headers_by_block)
      get("/headers", BeaconController, :get_headers)
    end

    scope "/config" do
      get("/spec", ConfigController, :get_spec)
    end

    scope "/node" do
      get("/health", NodeController, :health)
      get("/identity", NodeController, :identity)
      get("/version", NodeController, :version)
      get("/syncing", NodeController, :syncing)
      get("/peers", NodeController, :peers)
    end

    scope "/events" do
      get("/", EventsController, :subscribe)
    end
  end

  # Ethereum API Version 2
  scope "/eth/v2", BeaconApi.V2 do
    pipe_through(:api)

    scope "/beacon" do
      get("/blocks/:block_id", BeaconController, :get_block)
    end
  end

  scope "/api" do
    pipe_through(:api)
    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
  end

  # Catch-all route outside of any scope
  match(:*, "/*path", BeaconApi.ErrorController, :not_found)

  defp log_requests(conn, _opts) do
    base_message = "[BeaconAPI Router] Processing request: #{conn.method} - #{conn.request_path}"
    query = if conn.query_params != %{}, do: "Query: #{inspect(conn.query_params)}", else: ""
    body = if conn.body_params != %{}, do: "Body: #{inspect(conn.body_params)}", else: ""

    [base_message, query, body]
    |> Enum.join("\n\t")
    |> Logger.info()

    conn
  end
end
