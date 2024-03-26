defmodule BeaconApi.V2.BeaconController do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec
  alias BeaconApi.ErrorController
  alias BeaconApi.Utils
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Utils.BitList
  alias Types

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  def open_api_operation(:get_block),
    do: ApiSpec.spec().paths["/eth/v2/beacon/blocks/{block_id}"].get

  @spec get_block(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_block(conn, %{block_id: "head"}) do
    # TODO: determine head and return it
    conn |> block_not_found()
  end

  def get_block(conn, %{block_id: "finalized"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block(conn, %{block_id: "justified"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block(conn, %{block_id: "genesis"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block(conn, %{block_id: "0x" <> hex_block_id}) do
    with {:ok, block_root} <- Base.decode16(hex_block_id, case: :mixed),
         block <- Blocks.get_signed_block(block_root) do
      conn |> block_response(block)
    else
      nil -> conn |> block_not_found()
      _ -> conn |> ErrorController.bad_request("Invalid block ID: 0x#{hex_block_id}")
    end
  end

  def get_block(conn, %{block_id: block_id}) do
    with {slot, ""} when slot >= 0 <- Integer.parse(block_id),
         {:ok, block} <- BlockDb.get_block_by_slot(slot) do
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
      version: "deneb",
      execution_optimistic: true,
      finalized: false,
      data: to_json(block)
    })
  end

  defp to_json(attribute, module) when is_struct(attribute) do
    module.schema()
    |> Enum.map(fn {k, schema} ->
      {k, Map.fetch!(attribute, k) |> to_json(schema)}
    end)
    |> Map.new()
  end

  defp to_json(binary, {x, :bytes, _}) when x in [:list, :vector], do: to_json(binary)

  defp to_json(list, {x, schema, _}) when x in [:list, :vector],
    do: Enum.map(list, fn elem -> to_json(elem, schema) end)

  defp to_json(bitlist, {:bitlist, _}) do
    bitlist
    |> BitList.to_bytes()
    |> Utils.hex_encode()
  end

  defp to_json(v, _schema), do: to_json(v)

  def to_json(%name{} = v), do: to_json(v, name)
  def to_json({k, v}), do: {k, to_json(v)}
  def to_json(x) when is_binary(x), do: Utils.hex_encode(x)
  def to_json(v), do: inspect(v)

  def block_not_found(conn) do
    conn
    |> put_status(404)
    |> json(%{
      code: 404,
      message: "Block not found"
    })
  end
end
