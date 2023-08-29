defmodule SszTypes.PendingAttestation do
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
          aggregation_bits: SszTypes.bitlist(),
          data: SszTypes.AttestationData.t(),
          inclusion_delay: SszTypes.slot(),
          proposer_index: SszTypes.validator_index()
        }
end
