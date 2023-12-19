defmodule SszTypes.BeaconBlocksByRangeResponse do
  @moduledoc """
  Struct definition for `BeaconBlocksByRangeResponse`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :body
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          body: list(SszTypes.SignedBeaconBlock.t())
        }
end
