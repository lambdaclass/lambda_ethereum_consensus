defmodule BeaconApi.Router do
  use BeaconApi, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  # Ethereum API Version 1
  scope "/eth/v1", BeaconApi.V1 do
    pipe_through(:api)

    scope "/beacon" do
      get("/states/:state_id/root", BeaconController, :get_state_root)
    end
  end

  # Ethereum API Version 2
  scope "/eth/v2", BeaconApi.V2 do
    pipe_through(:api)

    scope "/beacon" do
    end
  end

  # Ethereum API Version 3
  scope "/eth/v3", BeaconApi.V3 do
    pipe_through(:api)
  end

  # Catch-all route outside of any scope
  match(:*, "/*path", BeaconApi.ErrorController, :not_found)
end
