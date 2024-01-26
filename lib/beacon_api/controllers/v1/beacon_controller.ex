defmodule BeaconApi.V1.BeaconController do
  alias BeaconApi.ApiSpec
  alias BeaconApi.ErrorController

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStore
  use BeaconApi, :controller

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  def open_api_operation(action) when is_atom(action) do
    # NOTE: action can take a bounded amount of values
    apply(__MODULE__, :"#{action}_operation", [])
  end

  def get_state_root_operation,
    do: ApiSpec.spec().paths["/eth/v1/beacon/states/{state_id}/root"].get

  @spec get_state_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_state_root(conn, %{state_id: state_id}) do
    case BeaconApi.Utils.parse_id(state_id) |> ForkChoice.Helpers.state_root_by_id() do
      {:ok, {root, execution_optimistic, finalized}} ->
        conn |> root_response(root, execution_optimistic, finalized)

      err ->
        case err do
          {:error, error_msg} ->
            conn |> ErrorController.internal_error("Error: #{inspect(error_msg)}")

          :not_found ->
            conn |> ErrorController.not_found(nil)

          :empty_slot ->
            conn |> ErrorController.not_found(nil)

          :invalid_id ->
            conn |> ErrorController.bad_request("Invalid state ID: #{state_id}")
        end
    end
  end

  def get_block_root_operation,
    do: ApiSpec.spec().paths["/eth/v1/beacon/blocks/{block_id}/root"].get

  @spec get_block_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_block_root(conn, %{block_id: "head"}) do
    # TODO: determine head and return it
    conn |> block_not_found()
  end

  def get_block_root(conn, %{block_id: "finalized"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block_root(conn, %{block_id: "justified"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block_root(conn, %{block_id: "genesis"}) do
    # TODO
    conn |> block_not_found()
  end

  def get_block_root(conn, %{block_id: "0x" <> hex_block_id}) do
    with {:ok, block_root} <- Base.decode16(hex_block_id, case: :mixed),
         %{} <- Blocks.get_block(block_root) do
      conn |> root_response(block_root, true, false)
    else
      nil -> conn |> block_not_found()
      _ -> conn |> ErrorController.bad_request("Invalid block ID: 0x#{hex_block_id}")
    end
  end

  def get_block_root(conn, %{block_id: block_id}) do
    with {slot, ""} when slot >= 0 <- Integer.parse(block_id),
         {:ok, block_root} <- BlockStore.get_block_root_by_slot(slot) do
      conn |> root_response(block_root, true, false)
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

  defp root_response(conn, root, execution_optimistic, finalized) do
    conn
    |> json(%{
      execution_optimistic: execution_optimistic,
      finalized: finalized,
      data: %{
        root: "0x" <> Base.encode16(root, case: :lower)
      }
    })
  end
end
