defmodule Types.AttesterSlashing do
  @moduledoc """
  Struct definition for `AttesterSlashing`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :attestation_1,
    :attestation_2
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          attestation_1: Types.IndexedAttestation.t(),
          attestation_2: Types.IndexedAttestation.t()
        }
end
