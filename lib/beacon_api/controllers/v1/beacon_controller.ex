defmodule BeaconApi.V1.BeaconController do
  alias BeaconApi.ApiSpec
  alias BeaconApi.ErrorController

  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Store.Blocks
  alias LambdaEthereumConsensus.Store.BlockStore
  use BeaconApi, :controller

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @doc """
  action is an atom that correspond to the controller action's function atoms declared on `BeaconApi.Router`
  """
  def open_api_operation(action) when is_atom(action) do
    apply(__MODULE__, :"#{action}_operation", [])
  end

  def get_state_root_operation,
    do: ApiSpec.spec().paths["/eth/v1/beacon/states/{state_id}/root"].get

  @spec get_state_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_state_root(conn, %{state_id: state_id}) do
    with {:ok, {root, execution_optimistic, finalized}} <-
           BeaconApi.Utils.parse_id(state_id) |> ForkChoice.Helpers.root_by_id(),
         {:ok, state_root} <- ForkChoice.Helpers.get_state_root(root) do
      conn |> root_response(state_root, execution_optimistic, finalized)
    else
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
         {:ok, _block} <- Blocks.get_block(block_root) do
      conn |> root_response(block_root, true, false)
    else
      :not_found -> conn |> block_not_found()
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
