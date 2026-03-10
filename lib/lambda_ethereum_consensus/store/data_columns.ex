defmodule LambdaEthereumConsensus.Store.DataColumns do
  @moduledoc """
  High-level interface for PeerDAS data column sidecars (Fulu / EIP-7594).

  Mirrors the `Store.Blobs` module used for blob sidecar management.
  Operates over the set of custody columns the local node is responsible for.
  """

  alias LambdaEthereumConsensus.Store.DataColumnDb
  alias Types.BlockInfo
  alias Types.DataColumnIdentifier
  alias Types.DataColumnSidecar

  @doc """
  Stores a list of data column sidecars. Returns the list of distinct block roots stored.
  """
  @spec add_columns([DataColumnSidecar.t()]) :: [Types.root()]
  def add_columns(sidecars) do
    sidecars
    |> Enum.map(&DataColumnDb.store_data_column/1)
    |> Enum.uniq()
  end

  @doc """
  Returns DataColumnIdentifiers for any custody columns not yet in the DB for this block.

  `custody_column_indices` should be the list of columns this node is responsible
  for (from `DasCore.get_custody_groups/2` + `DasCore.compute_columns_for_custody_group/1`).
  """
  @spec missing_columns_for_block(BlockInfo.t(), [Types.column_index()]) ::
          [DataColumnIdentifier.t()]
  def missing_columns_for_block(
        %BlockInfo{root: root, signed_block: signed_block},
        custody_column_indices
      ) do
    n_blobs = length(signed_block.message.body.blob_kzg_commitments)

    if n_blobs == 0 do
      []
    else
      Enum.filter(custody_column_indices, fn column_index ->
        not column_present?(root, column_index)
      end)
      |> Enum.map(&%DataColumnIdentifier{block_root: root, index: &1})
    end
  end

  defp column_present?(block_root, column_index) do
    DataColumnDb.has_column?(block_root, column_index)
  end
end
