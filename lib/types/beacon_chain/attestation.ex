defmodule Types.Attestation do
  @moduledoc """
  Struct definition for `AttestationMainnet`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :aggregation_bits,
    :data,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max validators per committee is 2048
          aggregation_bits: Types.bitlist(),
          data: Types.AttestationData.t(),
          signature: Types.bls_signature()
        }
end
