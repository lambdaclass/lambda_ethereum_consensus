defmodule BeaconApi.V1.BeaconController do
  alias BeaconApi.ErrorController
  use BeaconApi, :controller

  @spec get_state_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_state_root(conn, %{"state_id" => "head"}) do
    conn
    |> json(%{
      execution_optimistic: true,
      finalized: false,
      data: %{
        root: "0xbe41d3394dc8c461ab7049dbedba8944613ada8bd1743e091948f4d7b5ca8af36"
      }
    })
  end

  def get_state_root(conn, %{"state_id" => "finalized"}) do
    # TODO
    conn |> ErrorController.not_found(nil)
  end

  def get_state_root(conn, %{"state_id" => "justified"}) do
    # TODO
    conn |> ErrorController.not_found(nil)
  end

  def get_state_root(conn, %{"state_id" => "genesis"}) do
    # TODO
    conn |> ErrorController.not_found(nil)
  end

  def get_state_root(conn, %{
        "state_id" => "0xbe41d3394dc8c461ab7049dbedba8944613ada8bd1743e091948f4d7b5ca8af36"
      }) do
    conn
    |> json(%{
      execution_optimistic: true,
      finalized: false,
      data: %{
        root: "0xbe41d3394dc8c461ab7049dbedba8944613ada8bd1743e091948f4d7b5ca8af36"
      }
    })
  end

  def get_state_root(conn, %{"state_id" => "0x" <> _state_id}) do
    # TODO
    conn |> ErrorController.not_found(nil)
  end

  def get_state_root(conn, %{"state_id" => state_id}) do
    case Integer.parse(state_id) do
      {_slot, ""} ->
        # TODO
        conn |> ErrorController.not_found(nil)

      _ ->
        conn |> ErrorController.bad_request("Invalid state ID: #{state_id}")
    end
  end
end
