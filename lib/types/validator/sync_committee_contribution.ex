defmodule Types.SyncCommitteeContribution do
  @moduledoc """
  Struct definition for `SyncCommitteeContribution`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  use LambdaEthereumConsensus.Container
  alias LambdaEthereumConsensus.Utils.BitVector

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
          ChainSpec.get("SYNC_COMMITTEE_SIZE"),
          Constants.sync_committee_subnet_count()
        )}},
      {:signature, TypeAliases.bls_signature()}
    ]
  end

  def encode(%__MODULE__{} = map) do
    # NOTE: we do this because the SSZ NIF cannot decode bitstrings
    # TODO: remove when migrating to the new SSZ lib
    map
    |> Map.update!(:aggregation_bits, &BitVector.to_bytes/1)
  end

  def decode(%__MODULE__{} = map) do
    # NOTE: this isn't really needed
    aggregation_bits_count =
      div(
        ChainSpec.get("SYNC_COMMITTEE_SIZE"),
        Constants.sync_committee_subnet_count()
      )

    map
    |> Map.update!(:aggregation_bits, &BitVector.new(&1, aggregation_bits_count))
  end
end
