defmodule BeaconApi.V1.EventsController do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec
  alias BeaconApi.EventPubSub
  alias BeaconApi.Helpers

  require Logger

  @topic :finalized_checkpoint

  def open_api_operation(:subscribe),
    do: ApiSpec.spec().paths["/eth/v1/events"].get

  @spec subscribe(Plug.Conn.t(), any) :: Plug.Conn.t()
  def subscribe(conn, _params) do
    Logger.info("Subscribing to finalized checkpoint events")
    _finalized_checkpoint = get_current_finalized_checkpoint()

    EventPubSub.sse_subscribe(conn, @topic)
  end

  defp get_current_finalized_checkpoint() do
    x = Helpers.finalized_checkpoint()

    Logger.info(x |> inspect())

    x
  end
end
