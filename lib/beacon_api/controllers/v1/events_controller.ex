defmodule BeaconApi.V1.EventsController do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec
  alias BeaconApi.EventPubSub

  require Logger

  def open_api_operation(:subscribe),
    do: ApiSpec.spec().paths["/eth/v1/events"].get

  @spec subscribe(Plug.Conn.t(), any) :: Plug.Conn.t()
  def subscribe(conn, %{"topics" => topics}) do
    case parse_topics(topics) do
      {:ok, topics} ->
        EventPubSub.sse_subscribe(conn, topics)

      {:error, error} ->
        send_chunked_error(conn, error)
    end
  end

  def subscribe(conn, _params) do
    error =
      Jason.encode!(%{
        code: 400,
        message: "Missing field topics"
      })

    send_chunked_error(conn, error)
  end

  defp parse_topics(topics_string) do
    # topics is a string list in the form of: "finalized_checkpoint, block" we need to split it
    topics = topics_string |> String.split(",") |> Enum.map(&String.trim/1)
    not_implemented_topics = Enum.reject(topics, &EventPubSub.implemented_topic?/1)

    if Enum.empty?(not_implemented_topics) do
      {:ok, topics}
    else
      {:error,
       "Invalid topic/s #{inspect(not_implemented_topics)}. For now, only #{inspect(EventPubSub.implemented_topics())} are supported."}
    end
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
