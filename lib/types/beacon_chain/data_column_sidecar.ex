defmodule Types.DataColumnSidecar do
  @moduledoc """
  Struct definition for `DataColumnSidecar` (Fulu / PeerDAS, EIP-7594).
  Related definitions in `native/ssz_nif/src/types/`.

  A DataColumnSidecar carries all cells for one column index across all blobs
  in a block. The `index` field identifies which of the NUMBER_OF_COLUMNS (128)
  columns this sidecar represents. Together, 128 column sidecars reconstruct
  the full extended matrix for a block.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :index,
    :column,
    :kzg_commitments,
    :kzg_proofs,
    :signed_block_header,
    :kzg_commitments_inclusion_proof
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          index: Types.column_index(),
          # List of cells, one per blob in the block (up to MAX_BLOBS_PER_BLOCK_FULU)
          column: list(Types.cell()),
          # KZG commitments for each blob, matching the block body
          kzg_commitments: list(Types.kzg_commitment()),
          # KZG cell proofs, one per (blob, column) pair
          kzg_proofs: list(Types.kzg_proof()),
          signed_block_header: Types.SignedBeaconBlockHeader.t(),
          # Merkle proof of kzg_commitments in SignedBeaconBlock
          # Max size: KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH
          kzg_commitments_inclusion_proof: list(Types.bytes32())
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    max_blobs = ChainSpec.get("MAX_BLOBS_PER_BLOCK_FULU")
    max_blob_commitments = ChainSpec.get("MAX_BLOB_COMMITMENTS_PER_BLOCK")

    [
      index: TypeAliases.column_index(),
      column: {:list, TypeAliases.cell(), max_blobs},
      kzg_commitments: {:list, TypeAliases.kzg_commitment(), max_blob_commitments},
      kzg_proofs: {:list, TypeAliases.kzg_proof(), max_blobs},
      signed_block_header: Types.SignedBeaconBlockHeader,
      kzg_commitments_inclusion_proof:
        {:vector, TypeAliases.bytes32(),
         ChainSpec.get("KZG_COMMITMENTS_INCLUSION_PROOF_DEPTH")}
    ]
  end
end
