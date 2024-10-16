defmodule BeaconApi.ErrorController do
  require Logger
  use BeaconApi, :controller

  @spec bad_request(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  def bad_request(conn, message) do
    Logger.error("Bad request: #{message}, path: #{conn.request_path}")

    conn
    |> put_status(400)
    |> json(%{
      code: 400,
      message: "#{message}"
    })
  end

  @spec not_found(Plug.Conn.t(), any) :: Plug.Conn.t()
  def not_found(conn, _params) do
    Logger.error("Not found resource, path: #{conn.request_path}")

    conn
    |> put_status(404)
    |> json(%{
      code: 404,
      message: "Resource not found"
    })
  end

  @spec internal_error(Plug.Conn.t(), any) :: Plug.Conn.t()
  def internal_error(conn, _params) do
    Logger.error("Internal server error, path: #{conn.request_path}")

    conn
    |> put_status(500)
    |> json(%{
      code: 500,
      message: "Internal server error"
    })
  end
end
