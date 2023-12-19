defmodule Types.SignedBeaconBlock do
  @moduledoc """
  Struct definition for `SignedBeaconBlock`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :message,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          message: Types.BeaconBlock.t(),
          signature: Types.bls_signature()
        }
end
