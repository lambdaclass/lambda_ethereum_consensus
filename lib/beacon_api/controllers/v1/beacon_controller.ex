defmodule BeaconApi.V1.BeaconController do
  alias BeaconApi.ErrorController
  alias BeaconApi.Utils
  use BeaconApi, :controller

  @spec get_state_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_state_root(conn, params) do
    state_id =
      Map.get(params, "state_id")

    if state_id in [
         "head",
         "genesis",
         "finalized",
         "justified",
         "0xbe41d3394dc8c461ab7049dbedb8944613ada8bd1743e091948f4d7b5ca8af36"
       ] do
      conn
      |> json(%{
        execution_optimistic: true,
        finalized: false,
        data: %{
          root: "0xbe41d3394dc8c461ab7049dbedb8944613ada8bd1743e091948f4d7b5ca8af36"
        }
      })
    else
      if match?({_, ""}, Integer.parse(state_id)) or Utils.is_bytes32?(state_id) do
        conn |> ErrorController.not_found(nil)
      else
        conn |> ErrorController.bad_request("Invalid state ID: #{state_id}")
      end
    end
  end
end
