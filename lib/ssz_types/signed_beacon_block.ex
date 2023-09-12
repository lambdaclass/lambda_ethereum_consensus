defmodule SszTypes.SignedBeaconBlock do
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
          message: SszTypes.BeaconBlock.t(),
          signature: SszTypes.bls_signature()
        }
end
