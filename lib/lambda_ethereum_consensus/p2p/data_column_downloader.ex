defmodule LambdaEthereumConsensus.P2P.DataColumnDownloader do
  @moduledoc """
  Requests data column sidecars from peers via Req/Resp (Fulu / EIP-7594).

  Mirrors `BlobDownloader` but for the two new protocols:
  - `data_column_sidecars_by_range/1`
  - `data_column_sidecars_by_root/1`
  """

  require Logger

  alias LambdaEthereumConsensus.Libp2pPort
  alias LambdaEthereumConsensus.Metrics
  alias LambdaEthereumConsensus.P2P
  alias LambdaEthereumConsensus.P2P.ReqResp
  alias Types.DataColumnSidecar
  alias Types.Store

  @columns_by_range_protocol_id "/eth2/beacon_chain/req/data_column_sidecars_by_range/1/ssz_snappy"
  @columns_by_root_protocol_id "/eth2/beacon_chain/req/data_column_sidecars_by_root/1/ssz_snappy"

  @type on_columns :: (Store.t(), {:ok, [DataColumnSidecar.t()]} | {:error, any()} -> :ok)

  @default_retries 5

  @doc """
  Requests data column sidecars for a range of slots.

  `column_indices` specifies which columns to request (custody columns for this node).
  """
  @spec request_columns_by_range(
          Types.slot(),
          non_neg_integer(),
          [Types.column_index()],
          on_columns(),
          non_neg_integer()
        ) :: :ok
  def request_columns_by_range(
        slot,
        count,
        column_indices,
        on_columns,
        retries \\ @default_retries
      )

  def request_columns_by_range(_slot, 0, _column_indices, _on_columns, _retries), do: {:ok, []}
  def request_columns_by_range(_slot, _count, [], _on_columns, _retries), do: {:ok, []}

  def request_columns_by_range(slot, count, column_indices, on_columns, retries) do
    Logger.debug("Requesting data columns by range", slot: slot)

    peer_id =
      Enum.find_value(column_indices, fn idx -> P2P.Peerbook.get_peer_for_column(idx) end) ||
        P2P.Peerbook.get_peerdas_peer() ||
        get_some_peer()

    do_send_columns_by_range(peer_id, slot, count, column_indices, on_columns, retries)
  end

  defp do_send_columns_by_range(nil, _slot, _count, _column_indices, on_columns, _retries) do
    on_columns.(nil, {:error, :no_peers})
    :ok
  end

  defp do_send_columns_by_range(peer_id, slot, count, column_indices, on_columns, retries) do
    request =
      %Types.DataColumnSidecarsByRangeRequest{
        start_slot: slot,
        count: count,
        columns: column_indices
      }
      |> ReqResp.encode_request()

    Libp2pPort.send_async_request(
      peer_id,
      @columns_by_range_protocol_id,
      request,
      fn store, response ->
        Metrics.handler_span(
          "response_handler",
          "data_column_sidecars_by_range",
          fn ->
            handle_columns_by_range_response(
              store,
              response,
              peer_id,
              count,
              slot,
              column_indices,
              retries,
              on_columns
            )
          end
        )
      end
    )
  end

  defp handle_columns_by_range_response(
         store,
         response,
         peer_id,
         count,
         slot,
         column_indices,
         retries,
         on_columns
       ) do
    with {:ok, response_message} <- response,
         {:ok, columns} <- ReqResp.decode_response(response_message, DataColumnSidecar) do
      on_columns.(store, {:ok, columns})
    else
      {:error, reason} ->
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          Logger.debug("Retrying data column range request: #{inspect(reason)}", slot: slot)
          request_columns_by_range(slot, count, column_indices, on_columns, retries - 1)
          {:ok, store}
        else
          on_columns.(store, {:error, reason})
        end
    end
  end

  @doc """
  Requests data column sidecars by block root and column index.
  """
  @spec request_columns_by_root(
          [Types.DataColumnIdentifier.t()],
          on_columns(),
          non_neg_integer()
        ) :: :ok
  def request_columns_by_root(identifiers, on_columns, retries \\ @default_retries)

  def request_columns_by_root([], _on_columns, _retries), do: {:ok, []}

  def request_columns_by_root(identifiers, on_columns, retries) do
    Logger.debug("Requesting #{length(identifiers)} data columns.")

    column_indices = Enum.map(identifiers, & &1.index) |> Enum.uniq()

    peer_id =
      Enum.find_value(column_indices, fn idx -> P2P.Peerbook.get_peer_for_column(idx) end) ||
        P2P.Peerbook.get_peerdas_peer()

    do_send_columns_by_root(peer_id, identifiers, on_columns, retries)
  end

  defp do_send_columns_by_root(nil, _identifiers, on_columns, _retries) do
    on_columns.(nil, {:error, :no_peers})
    :ok
  end

  defp do_send_columns_by_root(peer_id, identifiers, on_columns, retries) do
    request =
      ReqResp.encode_request({identifiers, TypeAliases.data_column_sidecars_by_root_request()})

    Libp2pPort.send_async_request(
      peer_id,
      @columns_by_root_protocol_id,
      request,
      fn store, response ->
        Metrics.handler_span(
          "response_handler",
          "data_column_sidecars_by_root",
          fn ->
            handle_columns_by_root(store, response, peer_id, identifiers, retries, on_columns)
          end
        )
      end
    )
  end

  def handle_columns_by_root(store, response, peer_id, identifiers, retries, on_columns) do
    with {:ok, response_message} <- response,
         {:ok, columns} <- ReqResp.decode_response(response_message, DataColumnSidecar) do
      on_columns.(store, {:ok, columns})
    else
      {:error, reason} ->
        P2P.Peerbook.penalize_peer(peer_id)

        if retries > 0 do
          Logger.debug("Retrying data column root request.")
          request_columns_by_root(identifiers, on_columns, retries - 1)
          {:ok, store}
        else
          on_columns.(store, {:error, reason})
        end
    end
  end

  defp get_some_peer() do
    # TODO: (#1317) handle no-peers asynchronously
    P2P.Peerbook.get_some_peer()
  end
end
