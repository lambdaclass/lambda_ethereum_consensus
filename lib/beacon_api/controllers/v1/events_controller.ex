defmodule BeaconApi.V1.EventsController do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec
  alias BeaconApi.EventPubSub

  import BeaconApi.EventPubSub, only: [is_implemented_topic: 1]
  require Logger

  def open_api_operation(:subscribe),
    do: ApiSpec.spec().paths["/eth/v1/events"].get

  @spec subscribe(Plug.Conn.t(), any) :: Plug.Conn.t()
  def subscribe(conn, %{"topics" => topic}) when is_implemented_topic(topic),
    do: EventPubSub.sse_subscribe(conn, topic)

  def subscribe(conn, %{"topics" => not_implemented_topic}) do
    error =
      Jason.encode!(%{
        code: 400,
        message:
          "Invalid topic: #{not_implemented_topic}. For now we just support: #{inspect(EventPubSub.implemented_topics())}"
      })

    send_chunked_error(conn, error)
  end

  def subscribe(conn, _params) do
    error =
      Jason.encode!(%{
        code: 400,
        message: "Missing field topics"
      })

    send_chunked_error(conn, error)
  end

  defp send_chunked_error(conn, error) do
    conn
    |> Plug.Conn.send_chunked(400)
    |> Plug.Conn.chunk(error)
    |> case do
      {:ok, conn} -> Plug.Conn.halt(conn)
      {:error, _reason} -> Plug.Conn.halt(conn)
    end
  end
end
