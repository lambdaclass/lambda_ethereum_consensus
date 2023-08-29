defmodule SszTypes.SignedBeaconBlockHeader do
  @moduledoc """
  Struct definition for `SignedBeaconBlockHeader`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :message,
    :signature
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          message: SszTypes.beacon_block_header(),
          signature: SszTypes.bls_signature()
        }
end
