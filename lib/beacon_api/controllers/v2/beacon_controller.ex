defmodule BeaconApi.V2.BeaconController do
  alias BeaconApi.ErrorController
  alias LambdaEthereumConsensus.Store.BlockStore
  alias OpenApiSpex.Plug.CastAndValidate

  use BeaconApi, :controller
  use Phoenix.Controller
  plug CastAndValidate, json_render_error_v2: true

  @spec get_block(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_block(conn, %{"block_id" => "head"}) do
    # TODO: determine head and return it
    conn |> block_not_found()
  end

  def get_block(conn, %{"block_id" => "finalized"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block(conn, %{"block_id" => "justified"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block(conn, %{"block_id" => "genesis"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block(conn, %{"block_id" => "0x" <> hex_block_id}) do
    with {:ok, block_root} <- Base.decode16(hex_block_id, case: :mixed),
         {:ok, block} <- BlockStore.get_block(block_root) do
      conn |> block_response(block)
    else
      :not_found -> conn |> block_not_found()
      _ -> conn |> ErrorController.bad_request("Invalid block ID: 0x#{hex_block_id}")
    end
  end

  def get_block(conn, %{"block_id" => block_id}) do
    with {slot, ""} when slot >= 0 <- Integer.parse(block_id),
         {:ok, block} <- BlockStore.get_block_by_slot(slot) do
      conn |> block_response(block)
    else
      :not_found ->
        conn |> block_not_found()

      _ ->
        conn |> ErrorController.bad_request("Invalid block ID: #{block_id}")
    end
  end

  defp block_response(conn, block) do
    conn
    |> json(%{
      version: "capella",
      execution_optimistic: true,
      finalized: false,
      data: %{
        # TODO: return block as JSON
        message: inspect(block)
      }
    })
  end

  defp block_not_found(conn) do
    conn
    |> put_status(404)
    |> json(%{
      code: 404,
      message: "Block not found"
    })
  end
end
