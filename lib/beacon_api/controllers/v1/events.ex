defmodule BeaconApi.V1.Events do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec
  alias BeaconApi.Helpers
  alias SSE.Chunk

  require Logger

  @topic :finalized_checkpoint

  def open_api_operation(:subscribe),
  do: ApiSpec.spec().paths["/eth/v1/events"].get

  @spec subscribe(Plug.Conn.t(), any) :: Plug.Conn.t()
  def subscribe(conn, _params) do
    Logger.info("Subscribing to finalized checkpoint events")
    _finalized_checkpoint = get_current_finalized_checkpoint()

    Logger.info("Sending SSE stream")
    chunk = %Chunk{data: %{} |> Jason.encode!()}

    Logger.info(chunk |> inspect())
    conn
    |> SSE.stream({[@topic], chunk})
  end

  defp get_current_finalized_checkpoint() do
    x = Helpers.finalized_checkpoint()

    Logger.info(x |> inspect())

    x
  end
end
