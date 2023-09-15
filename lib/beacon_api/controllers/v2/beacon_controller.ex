defmodule BeaconApi.V1.BeaconController do
  alias LambdaEthereumConsensus.Store.BlockStore
  alias BeaconApi.ErrorController
  alias BeaconApi.Utils
  use BeaconApi, :controller

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

  def get_block(conn, %{"block_id" => "0x" <> block_id}) do
    block_root = Base.decode16(block_id, case: :mixed)

    case BlockStore.get_block(block_root) do
      {:ok, block} -> conn |> block_response(block)
      :not_found -> conn |> block_not_found()
    end
  end

  def get_block(conn, %{"block_id" => block_id}) do
    case Integer.parse(block_id) do
      {_slot, ""} ->
        # TODO
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
        message: Map.from_struct(block)
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
