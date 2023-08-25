defmodule SszTypes.IndexedAttestationMainnet do
  @moduledoc """
  Struct definition for `IndexedAttestationMainnet`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :attesting_indices,
    :data,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # max size is 2048
          attesting_indices: list(SszTypes.validator_index()),
          data: SszTypes.AttestationData.t(),
          signature: SszTypes.bls_signature()
        }
end
