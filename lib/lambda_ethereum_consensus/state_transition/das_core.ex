defmodule LambdaEthereumConsensus.StateTransition.DasCore do
  @moduledoc """
  Pure functions implementing PeerDAS (EIP-7594) das-core.md spec.

  These functions are stateless and operate on in-memory data structures.
  No networking or DB access is done here.
  """

  import Bitwise
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.BeaconBlockBody
  alias Types.BeaconBlockHeader
  alias Types.DataColumnSidecar
  alias Types.MatrixEntry
  alias Types.SignedBeaconBlockHeader

  @doc """
  Returns the set of custody groups for a node given its node_id.

  The `node_id` is a 256-bit integer (derived from the node's ENR key).
  Uses the swap-or-not shuffle algorithm over NUMBER_OF_CUSTODY_GROUPS.

  Spec: get_custody_groups(node_id, custody_group_count) in das-core.md
  """
  @spec get_custody_groups(Types.uint256(), non_neg_integer()) :: [Types.custody_index()]
  def get_custody_groups(node_id, custody_group_count) do
    n_groups = ChainSpec.get("NUMBER_OF_CUSTODY_GROUPS")
    collect_custody_groups(node_id, n_groups, custody_group_count, MapSet.new())
  end

  defp collect_custody_groups(current_id, n_groups, count, seen) when map_size(seen) < count do
    # Hash the 8-byte little-endian encoding of the low 64 bits of current_id
    seed = :crypto.hash(:sha256, <<current_id &&& 0xFFFFFFFFFFFFFFFF::little-size(64)>>)
    index = rem(current_id, n_groups)
    {:ok, shuffled} = Misc.compute_shuffled_index(index, n_groups, seed)

    new_seen =
      if MapSet.member?(seen, shuffled), do: seen, else: MapSet.put(seen, shuffled)

    collect_custody_groups(current_id + 1, n_groups, count, new_seen)
  end

  defp collect_custody_groups(_current_id, _n_groups, _count, seen) do
    MapSet.to_list(seen)
  end

  @doc """
  Returns the column indices assigned to a given custody group.

  Columns are interleaved across groups so adjacent columns belong to
  different groups, spreading data across the network more evenly.

  Spec: compute_columns_for_custody_group(custody_group) in das-core.md
  """
  @spec compute_columns_for_custody_group(Types.custody_index()) :: [Types.column_index()]
  def compute_columns_for_custody_group(custody_group) do
    n_columns = ChainSpec.get("NUMBER_OF_COLUMNS")
    n_groups = ChainSpec.get("NUMBER_OF_CUSTODY_GROUPS")
    columns_per_group = div(n_columns, n_groups)

    for column_offset <- 0..(columns_per_group - 1) do
      n_groups * column_offset + custody_group
    end
  end

  @doc """
  Returns all column indices for a given node, combining custody group assignment
  with per-group column computation.

  This is a convenience wrapper around `get_custody_groups/2` +
  `compute_columns_for_custody_group/1`.

  Spec: get_custody_columns(node_id, custody_group_count) in das-core.md
  """
  @spec get_custody_columns(Types.uint256(), non_neg_integer()) :: [Types.column_index()]
  def get_custody_columns(node_id, custody_group_count) do
    get_custody_groups(node_id, custody_group_count)
    |> Enum.flat_map(&compute_columns_for_custody_group/1)
  end

  @doc """
  Computes the extended matrix for a list of blobs by calling the KZG NIF
  for each blob to produce 128 cells and 128 proofs.

  Returns a flat list of MatrixEntry structs ordered by (row_index, column_index).

  Spec: compute_matrix(blobs) in das-core.md
  """
  @spec compute_matrix(list(Types.blob())) :: {:ok, [MatrixEntry.t()]} | {:error, binary()}
  def compute_matrix(blobs) do
    blobs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {blob, row_index}, {:ok, acc} ->
      case Kzg.compute_cells_and_kzg_proofs(blob) do
        {:ok, {cells, proofs}} ->
          {:cont, {:ok, acc ++ cells_to_entries(cells, proofs, row_index)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc """
  Recovers the full extended matrix from a partial set of received cells.

  For each row (blob), if enough cells are present (at least half = 64 of 128),
  uses erasure recovery to fill in the missing cells.

  Spec: recover_matrix(cells_and_proofs, blob_count) in das-core.md
  """
  @spec recover_matrix([MatrixEntry.t()], non_neg_integer()) ::
          {:ok, [MatrixEntry.t()]} | {:error, binary()}
  def recover_matrix(matrix, blob_count) do
    n_columns = ChainSpec.get("NUMBER_OF_COLUMNS")

    # Group entries by row
    by_row =
      Enum.group_by(matrix, & &1.row_index)

    0..(blob_count - 1)
    |> Enum.reduce_while({:ok, []}, fn row_index, {:ok, acc} ->
      row_entries = Map.get(by_row, row_index, [])

      case recover_row(row_entries, row_index, n_columns) do
        {:ok, entries} -> {:cont, {:ok, acc ++ entries}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp recover_row(row_entries, _row_index, n_columns) when length(row_entries) == n_columns do
    {:ok, row_entries}
  end

  defp recover_row(row_entries, row_index, _n_columns) do
    cell_indices = Enum.map(row_entries, & &1.column_index)
    cells = Enum.map(row_entries, & &1.cell)

    case Kzg.recover_cells_and_kzg_proofs(cell_indices, cells) do
      {:ok, {recovered_cells, recovered_proofs}} ->
        {:ok, cells_to_entries(recovered_cells, recovered_proofs, row_index)}

      {:error, reason} ->
        {:error, "row #{row_index}: #{reason}"}
    end
  end

  @doc """
  Constructs DataColumnSidecar structs from a signed block and its
  computed cells+proofs (one {cells, proofs} pair per blob).

  Returns a list of NUMBER_OF_COLUMNS sidecars, one per column index.

  Spec: get_data_column_sidecars(signed_block, cells_and_kzg_proofs) in das-core.md
  """
  @spec get_data_column_sidecars(
          Types.SignedBeaconBlock.t(),
          list({list(Types.cell()), list(Kzg.proof())})
        ) :: {:ok, [DataColumnSidecar.t()]} | {:error, binary()}
  def get_data_column_sidecars(%{message: block} = signed_block, cells_and_kzg_proofs) do
    n_columns = ChainSpec.get("NUMBER_OF_COLUMNS")

    signed_block_header = compute_signed_block_header(signed_block)
    kzg_commitments_inclusion_proof = compute_kzg_commitments_inclusion_proof(block.body)
    kzg_commitments = block.body.blob_kzg_commitments

    sidecars =
      for column_index <- 0..(n_columns - 1) do
        {column_cells, column_proofs} =
          cells_and_kzg_proofs
          |> Enum.map(fn {cells, proofs} ->
            {Enum.at(cells, column_index), Enum.at(proofs, column_index)}
          end)
          |> Enum.unzip()

        %DataColumnSidecar{
          index: column_index,
          column: column_cells,
          kzg_commitments: kzg_commitments,
          kzg_proofs: column_proofs,
          signed_block_header: signed_block_header,
          kzg_commitments_inclusion_proof: kzg_commitments_inclusion_proof
        }
      end

    {:ok, sidecars}
  end

  @doc """
  Verifies that all custody column sidecars for a block are valid by
  batch-verifying their KZG cell proofs.

  Returns true if all proofs are valid.
  """
  @spec columns_data_available?(Types.root(), [DataColumnSidecar.t()]) :: boolean()
  def columns_data_available?(_block_root, []), do: true

  def columns_data_available?(block_root, sidecars) do
    # Verify all sidecars belong to the expected block
    all_for_block =
      Enum.all?(sidecars, fn %DataColumnSidecar{
                               signed_block_header: %{message: %{body_root: _}}
                             } = sidecar ->
        sidecar_root =
          SszEx.hash_tree_root!(sidecar.signed_block_header.message, Types.BeaconBlockHeader)

        sidecar_root == block_root
      end)

    if all_for_block do
      verify_data_column_sidecars_kzg(sidecars)
    else
      false
    end
  end

  defp cells_to_entries(cells, proofs, row_index) do
    cells
    |> Enum.zip(proofs)
    |> Enum.with_index()
    |> Enum.map(fn {{cell, proof}, column_index} ->
      %MatrixEntry{
        cell: cell,
        kzg_proof: proof,
        column_index: column_index,
        row_index: row_index
      }
    end)
  end

  # Batch-verifies cell KZG proofs for all given sidecars.
  defp verify_data_column_sidecars_kzg(sidecars) do
    {commitments, cell_indices, cells, proofs} =
      sidecars
      |> Enum.flat_map(fn sidecar ->
        column_index = sidecar.index

        sidecar.kzg_commitments
        |> Enum.zip(sidecar.column)
        |> Enum.zip(sidecar.kzg_proofs)
        |> Enum.map(fn {{commitment, cell}, proof} ->
          {commitment, column_index, cell, proof}
        end)
      end)
      |> Enum.reduce({[], [], [], []}, fn {c, ci, cell, p}, {cs, cis, cells, ps} ->
        {[c | cs], [ci | cis], [cell | cells], [p | ps]}
      end)
      |> then(fn {cs, cis, cells, ps} ->
        {Enum.reverse(cs), Enum.reverse(cis), Enum.reverse(cells), Enum.reverse(ps)}
      end)

    Kzg.cell_kzg_proof_batch_valid?(commitments, cell_indices, cells, proofs)
  end

  # Computes a signed block header from a signed block (strips the body).
  defp compute_signed_block_header(%{message: block, signature: signature}) do
    block_header = %BeaconBlockHeader{
      slot: block.slot,
      proposer_index: block.proposer_index,
      parent_root: block.parent_root,
      state_root: block.state_root,
      body_root: Ssz.hash_tree_root!(block.body)
    }

    %SignedBeaconBlockHeader{message: block_header, signature: signature}
  end

  # Computes the Merkle proof of `blob_kzg_commitments` within BeaconBlockBody.
  # This is a path of KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH (= 4) hashes.
  defp compute_kzg_commitments_inclusion_proof(%BeaconBlockBody{} = body) do
    commitments_tree_index =
      BeaconBlockBody.schema()
      |> Enum.find_index(&match?({:blob_kzg_commitments, _}, &1))

    body_height = BeaconBlockBody.schema() |> Enum.count() |> :math.log2() |> ceil()

    BeaconBlockBody.schema()
    |> Enum.map(fn {name, schema} -> Map.fetch!(body, name) |> SszEx.hash_tree_root!(schema) end)
    |> SszEx.Merkleization.compute_merkle_proof(commitments_tree_index, body_height)
  end
end
