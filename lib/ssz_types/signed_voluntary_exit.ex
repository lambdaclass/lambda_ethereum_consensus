defmodule SszTypes.SignedVoluntaryExit do
  @moduledoc """
  Struct definition for `SignedVoluntaryExit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :message,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          message: SszTypes.VoluntaryExit,
          signature: SszTypes.bls_signature()
        }
end
