defmodule SszTypes.BeaconBlocksByRangeRequest do
  @moduledoc """
  Struct definition for `BeaconBlocksByRangeRequest`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  @enforce_keys [:start_slot, :count]
  defstruct [
    :start_slot,
    :count,
    step: 1
  ]

  @type t :: %__MODULE__{
          start_slot: SszTypes.slot(),
          count: SszTypes.uint64(),
          # Deprecated, must be set to 1
          step: SszTypes.uint64()
        }
end
