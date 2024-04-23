defmodule Types.BlobSidecar do
  @moduledoc """
  Struct definition for `BlobSidecar`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :index,
    :blob,
    :kzg_commitment,
    :kzg_proof,
    :signed_block_header,
    :kzg_commitment_inclusion_proof
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          index: Types.blob_index(),
          blob: Types.blob(),
          kzg_commitment: Types.kzg_commitment(),
          kzg_proof: Types.kzg_proof(),
          signed_block_header: Types.SignedBeaconBlockHeader.t(),
          # Max size: KZG_COMMITMENT_INCLUSION_PROOF_DEPTH
          kzg_commitment_inclusion_proof: list(Types.bytes32())
        }

  @impl LambdaEthereumConsensus.Container
  def schema() do
    [
      index: TypeAliases.blob_index(),
      blob: TypeAliases.blob(),
      kzg_commitment: TypeAliases.kzg_commitment(),
      kzg_proof: TypeAliases.kzg_proof(),
      signed_block_header: Types.SignedBeaconBlockHeader,
      kzg_commitment_inclusion_proof:
        {:vector, TypeAliases.bytes32(), ChainSpec.get("KZG_COMMITMENT_INCLUSION_PROOF_DEPTH")}
    ]
  end
end
