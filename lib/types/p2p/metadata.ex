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

  def encode(%__MODULE__{} = map) do
    # NOTE: we do this because the SSZ NIF cannot decode bitstrings
    # TODO: remove when migrating to the new SSZ lib
    map
    |> Map.update!(:attnets, &bitstring_to_binary/1)
    |> Map.update!(:syncnets, &bitstring_to_binary/1)
  end

  def decode(%__MODULE__{} = map) do
    # NOTE: this isn't really needed
    subnet_count = ChainSpec.get("ATTESTATION_SUBNET_COUNT")
    syncnet_count = Constants.sync_committee_subnet_count()

    map
    |> Map.update!(:attnets, &BitVector.new(&1, subnet_count))
    |> Map.update!(:syncnets, &BitVector.new(&1, syncnet_count))
  end

  defp bitstring_to_binary(bs) do
    padding = byte_size(bs) * 8 - bit_size(bs)
    <<bs::bitstring, 0::size(padding)>>
  end
end
