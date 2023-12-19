defmodule Types.SignedBLSToExecutionChange do
  @moduledoc """
  Struct definition for `SignedBLSToExecutionChange`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :message,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          message: Types.BLSToExecutionChange.t(),
          signature: Types.bls_signature()
        }
end
