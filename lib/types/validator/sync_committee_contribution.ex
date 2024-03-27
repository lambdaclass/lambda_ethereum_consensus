defmodule Types.SyncCommitteeContribution do
  @moduledoc """
  Struct definition for `SyncCommitteeContribution`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container

  fields = [
    :slot,
    :beacon_block_root,
    :subcommittee_index,
    :aggregation_bits,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          slot: Types.slot(),
          beacon_block_root: Types.root(),
          subcommittee_index: Types.uint64(),
          aggregation_bits: Types.bitvector(),
          signature: Types.bls_signature()
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:slot, TypeAliases.slot()},
      {:beacon_block_root, TypeAliases.root()},
      {:subcommittee_index, TypeAliases.uint64()},
      {:aggregation_bits,
       {:bitvector,
        div(
          ChainSpec.get("MAX_VALIDATORS_PER_COMMITTEE"),
          Constants.sync_committee_subnet_count()
        )}},
      {:signature, TypeAliases.bls_signature()}
    ]
  end
end
