defmodule Types.MatrixEntry do
  @moduledoc """
  SSZ Container for `MatrixEntry` (Fulu / PeerDAS, EIP-7594).
  Also used internally by DAS core logic.

  The extended matrix is a 2D grid of cells:
  - rows correspond to blobs
  - columns correspond to the NUMBER_OF_COLUMNS (128) data columns

  A MatrixEntry holds one cell at position (row_index, column_index) together
  with its KZG proof and the blob/column indices needed for proof verification.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :cell,
    :kzg_proof,
    :column_index,
    :row_index
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          cell: Types.cell(),
          kzg_proof: Types.kzg_proof(),
          column_index: Types.column_index(),
          row_index: Types.row_index()
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      {:cell, TypeAliases.cell()},
      {:kzg_proof, TypeAliases.kzg_proof()},
      {:column_index, TypeAliases.column_index()},
      {:row_index, TypeAliases.row_index()}
    ]
  end
end
