defmodule BeaconApi.V1.BeaconController do
  use BeaconApi, :controller

  @spec get_state_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_state_root(conn, params) do
    json(conn, %{
      id: Map.get(params, "state_id"),
      root: "0xbe41d3394dc8c461ab7049dbedb8944613ada8bd1743e091948f4d7b5ca8af36"
    })
  end
end
