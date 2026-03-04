defmodule LambdaEthereumConsensus.StateTransition.DasCore do
  @moduledoc """
  Pure functions implementing PeerDAS (EIP-7594) das-core.md spec.

  These functions are stateless and operate on in-memory data structures.
  No networking or DB access is done here.
  """

  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.BeaconBlockBody

  # 2^256 - 1, the maximum value of a uint256, used for overflow prevention
  # in get_custody_groups as specified in das-core.md.
  @uint256_max (1 <<< 256) - 1
  alias Types.BeaconBlockHeader
  alias Types.DataColumnSidecar
  alias Types.MatrixEntry
  alias Types.SignedBeaconBlockHeader

  @doc """
  Returns the sorted set of custody groups for a node given its node_id.

  The `node_id` is a 256-bit integer (derived from the node's ENR key).
  Uses SHA256(uint256_le(current_id))[0:8] mod NUMBER_OF_CUSTODY_GROUPS
  to assign custody groups, iterating until the required count is reached.

  Spec: get_custody_groups(node_id, custody_group_count) in das-core.md
  """
  @spec get_custody_groups(Types.uint256(), non_neg_integer()) :: [Types.custody_index()]
  def get_custody_groups(node_id, custody_group_count) do
    n_groups = ChainSpec.get("NUMBER_OF_CUSTODY_GROUPS")

    if custody_group_count > n_groups do
      raise ArgumentError,
            "custody_group_count (#{custody_group_count}) > NUMBER_OF_CUSTODY_GROUPS (#{n_groups})"
    end

    if custody_group_count == n_groups do
      Enum.to_list(0..(n_groups - 1))
    else
      collect_custody_groups(node_id, n_groups, custody_group_count, %{}, 0)
    end
  end

  defp collect_custody_groups(_current_id, _n_groups, count, seen, seen_size)
       when seen_size >= count do
    seen |> Map.keys() |> Enum.sort()
  end

  defp collect_custody_groups(current_id, n_groups, count, seen, seen_size) do
    # Spec: hash(uint_to_bytes(current_id)) where current_id is uint256 little-endian.
    # Take first 8 bytes as uint64, then modulo NUMBER_OF_CUSTODY_GROUPS.
    hash = SszEx.hash(<<current_id::unsigned-integer-little-size(256)>>)
    custody_group = Misc.bytes_to_uint64(hash) |> rem(n_groups)

    {new_seen, new_size} =
      if Map.has_key?(seen, custody_group),
        do: {seen, seen_size},
        else: {Map.put(seen, custody_group, true), seen_size + 1}

    next_id = if current_id == @uint256_max, do: 0, else: current_id + 1
    collect_custody_groups(next_id, n_groups, count, new_seen, new_size)
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
  Returns the custody column indices for this node, reading node_id from
  the Application environment (set by Libp2pPort at startup) and
  CUSTODY_REQUIREMENT from ChainSpec.

  Falls back to node_id=0 if discovery is disabled or the port has not
  yet reported its identity; in that case Libp2pPort logs a warning.
  """
  @spec get_local_custody_columns() :: [Types.column_index()]
  def get_local_custody_columns() do
    node_id = Application.get_env(:lambda_ethereum_consensus, :node_id, 0)
    custody_group_count = ChainSpec.get("CUSTODY_REQUIREMENT")
    get_custody_columns(node_id, custody_group_count)
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
  checking structural constraints and batch-verifying their KZG cell proofs.

  Returns true if all sidecars are structurally valid and all proofs pass.
  """
  @spec columns_data_available?(Types.root(), [Types.kzg_commitment()], [DataColumnSidecar.t()]) ::
          boolean()
  def columns_data_available?(_block_root, _blob_kzg_commitments, []), do: true

  def columns_data_available?(block_root, blob_kzg_commitments, sidecars) do
    n = length(blob_kzg_commitments)

    all_valid =
      Enum.all?(sidecars, fn sidecar ->
        sidecar_root =
          SszEx.hash_tree_root!(sidecar.signed_block_header.message, Types.BeaconBlockHeader)

        sidecar_root == block_root and
          sidecar.kzg_commitments == blob_kzg_commitments and
          length(sidecar.column) == n and
          length(sidecar.kzg_proofs) == n
      end)

    if all_valid do
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
