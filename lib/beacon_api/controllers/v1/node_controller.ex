defmodule BeaconApi.V1.NodeController do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:health),
    do: ApiSpec.spec().paths["/eth/v1/node/health"].get

  @spec health(Plug.Conn.t(), any) :: Plug.Conn.t()
  def health(conn, _params) do
    conn
    |> send_resp(200, "")
  end
end
