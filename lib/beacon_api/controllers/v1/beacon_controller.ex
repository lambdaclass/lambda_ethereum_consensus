defmodule BeaconApi.V1.BeaconController do
  use BeaconApi, :controller

  alias BeaconApi.ApiSpec
  alias BeaconApi.ErrorController
  alias BeaconApi.Helpers
  alias BeaconApi.Utils
  alias LambdaEthereumConsensus.Beacon.BeaconChain
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Store.BlockDb
  alias LambdaEthereumConsensus.Store.Blocks

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  # NOTE: this function is required by OpenApiSpex, and should return the information
  #  of each specific endpoint. We just return the specific entry from the parsed spec.
  def open_api_operation(:get_genesis),
    do: ApiSpec.spec().paths["/eth/v1/beacon/genesis"].get

  def open_api_operation(:get_state_root),
    do: ApiSpec.spec().paths["/eth/v1/beacon/states/{state_id}/root"].get

  def open_api_operation(:get_block_root),
    do: ApiSpec.spec().paths["/eth/v1/beacon/blocks/{block_id}/root"].get

  def open_api_operation(:get_finality_checkpoints),
    do: ApiSpec.spec().paths["/eth/v1/beacon/states/{state_id}/finality_checkpoints"].get

  @spec get_genesis(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_genesis(conn, _params) do
    conn
    |> json(%{
      "data" => %{
        "genesis_time" => BeaconChain.get_genesis_time(),
        "genesis_validators_root" =>
          ChainSpec.get_genesis_validators_root() |> Utils.hex_encode(),
        "genesis_fork_version" => ChainSpec.get("GENESIS_FORK_VERSION") |> Utils.hex_encode()
      }
    })
  end

  @spec get_state_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_state_root(conn, %{state_id: state_id}) do
    case BeaconApi.Utils.parse_id(state_id) |> Helpers.state_root_by_state_id() do
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
         {:ok, block_root} <- BlockDb.get_block_root_by_slot(slot) do
      conn |> root_response(block_root, true, false)
    else
      :not_found ->
        conn |> block_not_found()

      _ ->
        conn |> ErrorController.bad_request("Invalid block ID: #{block_id}")
    end
  end

  @spec get_finality_checkpoints(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_finality_checkpoints(conn, %{state_id: state_id}) do
    case BeaconApi.Utils.parse_id(state_id) |> Helpers.finality_checkpoint_by_id() do
      {:ok,
       {previous_justified_checkpoint, current_justified_checkpoint, finalized_checkpoint,
        execution_optimistic, finalized}} ->
        conn
        |> finality_checkpoints_response(
          previous_justified_checkpoint,
          current_justified_checkpoint,
          finalized_checkpoint,
          execution_optimistic,
          finalized
        )

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

  defp finality_checkpoints_response(
         conn,
         previous_justified_checkpoint,
         current_justified_checkpoint,
         finalized_checkpoint,
         execution_optimistic,
         finalized
       ) do
    conn
    |> json(%{
      execution_optimistic: execution_optimistic,
      finalized: finalized,
      data: %{
        previous_justified: %{
          epoch: previous_justified_checkpoint.epoch,
          root: Utils.hex_encode(previous_justified_checkpoint.root)
        },
        current_justified: %{
          epoch: current_justified_checkpoint.epoch,
          root: Utils.hex_encode(current_justified_checkpoint.root)
        },
        finalized: %{
          epoch: finalized_checkpoint.epoch,
          root: Utils.hex_encode(finalized_checkpoint.root)
        }
      }
    })
  end
end
