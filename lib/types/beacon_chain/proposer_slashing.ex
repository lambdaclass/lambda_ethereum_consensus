defmodule Types.ProposerSlashing do
  @moduledoc """
  Struct definition for `ProposerSlashing`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :signed_header_1,
    :signed_header_2
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          signed_header_1: Types.SignedBeaconBlockHeader.t(),
          signed_header_2: Types.SignedBeaconBlockHeader.t()
        }
end
