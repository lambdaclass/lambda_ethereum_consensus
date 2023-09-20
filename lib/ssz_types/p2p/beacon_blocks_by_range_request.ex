defmodule SszTypes.BeaconBlocksByRangeRequest do
  @moduledoc """
  Struct definition for `BeaconBlocksByRangeRequest`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :start_slot,
    :count,
    :step
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          start_slot: SszTypes.slot(),
          count: SszTypes.uint64(),
          # Deprecated, must be set to 1
          step: SszTypes.uint64()
        }
end
