defmodule Types.Metadata do
  @moduledoc """
  Struct definition for `Metadata`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  alias LambdaEthereumConsensus.Utils.BitVector

  fields = [
    :seq_number,
    :attnets,
    :syncnets
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          seq_number: Types.uint64(),
          attnets: Types.bitvector(),
          syncnets: Types.bitvector()
        }

  def schema(),
    do: [
      seq_number: TypeAliases.uint64(),
      attnets: {:bitvector, ChainSpec.get("ATTESTATION_SUBNET_COUNT")},
      syncnets: {:bitvector, Constants.sync_committee_subnet_count()}
    ]

  def empty() do
    attnets = ChainSpec.get("ATTESTATION_SUBNET_COUNT") |> BitVector.new()
    syncnets = Constants.sync_committee_subnet_count() |> BitVector.new()
    %__MODULE__{seq_number: 0, attnets: attnets, syncnets: syncnets}
  end

  def encode(%__MODULE__{} = map) do
    # NOTE: we do this because the SSZ NIF cannot decode bitstrings
    # TODO: remove when migrating to the new SSZ lib
    map
    |> Map.update!(:attnets, &BitVector.to_bytes/1)
    |> Map.update!(:syncnets, &BitVector.to_bytes/1)
  end

  def decode(%__MODULE__{} = map) do
    # NOTE: this isn't really needed
    subnet_count = ChainSpec.get("ATTESTATION_SUBNET_COUNT")
    syncnet_count = Constants.sync_committee_subnet_count()

    map
    |> Map.update!(:attnets, &BitVector.new(&1, subnet_count))
    |> Map.update!(:syncnets, &BitVector.new(&1, syncnet_count))
  end
end
