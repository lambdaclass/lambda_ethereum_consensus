defmodule SszTypes.BeaconBlocksByRootResponse do
  @moduledoc """
  Struct definition for `BeaconBlocksByRootResponse`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :blocks
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          blocks: list(SszTypes.SignedBeaconBlock.t())
        }
end
