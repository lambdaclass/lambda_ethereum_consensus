defmodule BeaconApi.V1.BeaconController do
  alias BeaconApi.ErrorController
  alias LambdaEthereumConsensus.Store.BlockStore
  alias OpenApiSpex.Plug.CastAndValidate

  use BeaconApi, :controller
  plug CastAndValidate, json_render_error_v2: true

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

  @spec get_block_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_block_root(conn, %{"block_id" => "head"}) do
    # TODO: determine head and return it
    conn |> block_not_found()
  end

  def get_block_root(conn, %{"block_id" => "finalized"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block_root(conn, %{"block_id" => "justified"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block_root(conn, %{"block_id" => "genesis"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block_root(conn, %{"block_id" => "0x" <> hex_block_id}) do
    with {:ok, block_root} <- Base.decode16(hex_block_id, case: :mixed),
         {:ok, _signed_block} <- BlockStore.get_block(block_root) do
      conn |> root_response(block_root)
    else
      :not_found -> conn |> block_not_found()
      _ -> conn |> ErrorController.bad_request("Invalid block ID: 0x#{hex_block_id}")
    end
  end

  def get_block_root(conn, %{"block_id" => block_id}) do
    with {slot, ""} when slot >= 0 <- Integer.parse(block_id),
         {:ok, block_root} <- BlockStore.get_block_root_by_slot(slot) do
      conn |> root_response(block_root)
    else
      :not_found ->
        conn |> block_not_found()

      _ ->
        conn |> ErrorController.bad_request("Invalid block ID: #{block_id}")
    end
  end

  defp block_not_found(conn) do
    conn
    |> put_status(404)
    |> json(%{
      code: 404,
      message: "Block not found"
    })
  end

  defp root_response(conn, root) do
    conn
    |> json(%{
      execution_optimistic: true,
      finalized: false,
      data: %{
        root: "0x" <> Base.encode16(root, case: :lower)
      }
    })
  end
end
