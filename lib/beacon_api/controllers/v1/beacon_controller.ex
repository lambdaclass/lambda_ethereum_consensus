defmodule BeaconApi.V1.BeaconController do
  alias BeaconApi.ErrorController
  alias LambdaEthereumConsensus.ForkChoice
  alias LambdaEthereumConsensus.Store.BlockStore
  use BeaconApi, :controller

  @spec get_state_root(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_state_root(conn, %{"state_id" => state_id}) do
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
      conn |> root_response(block_root, true, false)
    else
      :not_found -> conn |> block_not_found()
      _ -> conn |> ErrorController.bad_request("Invalid block ID: 0x#{hex_block_id}")
    end
  end

  def get_block_root(conn, %{"block_id" => block_id}) do
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

  @spec get_block_header(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_block_header(conn, %{"block_id" => block_id}) do
    with {:ok, {root, execution_optimistic, finalized}} <-
           BeaconApi.Utils.parse_id(block_id) |> ForkChoice.Helpers.root_by_id(),
         {:ok, signed_block} <- BlockStore.get_block(root) do
      conn |> header_response(root, signed_block, execution_optimistic, finalized)
    else
      {:error, error_msg} ->
        conn |> ErrorController.internal_error("Error: #{inspect(error_msg)}")

      :not_found ->
        conn |> ErrorController.not_found(nil)

      :empty_slot ->
        conn |> ErrorController.not_found(nil)

      :invalid_id ->
        conn |> ErrorController.bad_request("Invalid block ID: #{block_id}")
    end
  end

  @spec get_block_headers(Plug.Conn.t(), any) :: Plug.Conn.t()
  def get_block_headers(conn, %{"slot" => slot, "parent_root" => parent_root} = _params) do
    with raw_block_id <- get_block_id_from_slot_or_parent_root(slot, parent_root),
         {:ok, {root, execution_optimistic, finalized}} <-
           BeaconApi.Utils.parse_id(raw_block_id) |> ForkChoice.Helpers.root_by_id(),
         {:ok, signed_block} <-
           BlockStore.get_block(root),
         {:ok, signed_block} <-
           validate_block_matches_with_optional_parent_root_and_slot(
             signed_block,
             parent_root,
             raw_block_id
           ) do
      conn |> header_response(root, signed_block, execution_optimistic, finalized)
    else
      {:error, error_msg} ->
        conn |> ErrorController.internal_error("Error: #{inspect(error_msg)}")

      :not_found ->
        conn |> ErrorController.not_found(nil)

      :empty_slot ->
        conn |> ErrorController.not_found(nil)
    end
  end

  defp get_block_id_from_slot_or_parent_root(slot, parent_root) do
    case {slot, parent_root} do
      {nil, nil} ->
        "head"

      {nil, parent_root} ->
        parent_block = BlockStore.get_block(parent_root)
        parent_slot = parent_block.message.slot
        # TODO: ignore any skip-slots immediatly following the parent
        parent_slot + 1

      {slot, _parent_block} ->
        slot
    end
  end

  defp validate_block_matches_with_optional_parent_root_and_slot(signed_block, nil, _slot),
    do: {:ok, signed_block}

  defp validate_block_matches_with_optional_parent_root_and_slot(signed_block, parent_root, slot) do
    if signed_block.message.parent_root == parent_root do
      {:ok, signed_block}
    else
      {:error, "no canonical block at slot #{slot} with parent root #{parent_root}"}
    end
  end

  defp header_response(conn, root, signed_block, execution_optimistic, finalized) do
    conn
    |> json(%{
      execution_optimistic: execution_optimistic,
      finalized: finalized,
      data: %{
        root: "0x" <> Base.encode16(root, case: :lower),
        canonical: true,
        header: %{
          message: %{
            slot: signed_block.message.slot,
            proposer_index: signed_block.message.proposer_index,
            parent_root: signed_block.message.parent_root,
            state_root: signed_block.message.state_root,
            body_root: root
          },
          signature: signed_block.signature
        }
      }
    })
  end
end
