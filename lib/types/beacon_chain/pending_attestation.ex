defmodule Types.PendingAttestation do
  @moduledoc """
  Struct definition for `PendingAttestation`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :aggregation_bits,
    :data,
    :inclusion_delay,
    :proposer_index
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          aggregation_bits: Types.bitlist(),
          data: Types.AttestationData.t(),
          inclusion_delay: Types.slot(),
          proposer_index: Types.validator_index()
        }
end
