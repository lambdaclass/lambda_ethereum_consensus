defmodule Types.MatrixEntry do
  @moduledoc """
  In-memory struct for `MatrixEntry` (Fulu / PeerDAS, EIP-7594).
  Not SSZ-serialized; used internally by DAS core logic.

  The extended matrix is a 2D grid of cells:
  - rows correspond to blobs (up to MAX_BLOBS_PER_BLOCK_FULU)
  - columns correspond to the NUMBER_OF_COLUMNS (128) data columns

  A MatrixEntry holds one cell at position (row_index, column_index) together
  with its KZG proof and the blob/column indices needed for proof verification.
  """

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
end
