defmodule Types.SignedVoluntaryExit do
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
          message: Types.VoluntaryExit.t(),
          signature: Types.bls_signature()
        }
end
