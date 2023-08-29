defmodule SszTypes.AttesterSlashing do
  @moduledoc """
  Struct definition for `AttestationMainnet`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :attestation_1,
    :attestation_2
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          attestation_1: SszTypes.IndexedAttestation.t(),
          attestation_2: SszTypes.IndexedAttestation.t()
        }
end
