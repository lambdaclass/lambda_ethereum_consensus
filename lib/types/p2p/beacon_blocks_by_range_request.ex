defmodule Types.BeaconBlocksByRangeRequest do
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
          start_slot: Types.slot(),
          count: Types.uint64(),
          # Deprecated, must be set to 1
          step: Types.uint64()
        }
end
