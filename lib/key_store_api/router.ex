defmodule KeyStoreApi.Router do
  use KeyStoreApi, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: KeyStoreApi.ApiSpec)
  end

  scope "/api" do
    pipe_through(:api)
    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
  end

  # Catch-all route outside of any scope
  match(:*, "/*path", KeyStoreApi.ErrorController, :not_found)
end
