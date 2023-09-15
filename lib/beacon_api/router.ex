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
      get("/blocks/:block_id/root", BeaconController, :get_block_root)
    end
  end

  # Ethereum API Version 2
  scope "/eth/v2", BeaconApi.V2 do
    pipe_through(:api)

    scope "/beacon" do
      get("/blocks/:block_id", BeaconController, :get_block)
    end
  end

  # Catch-all route outside of any scope
  match(:*, "/*path", BeaconApi.ErrorController, :not_found)
end
