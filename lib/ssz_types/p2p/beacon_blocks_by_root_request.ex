defmodule SszTypes.BeaconBlocksByRootRequest do
  @moduledoc """
  Struct definition for `BeaconBlocksByRootRequest`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :block_roots
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          block_roots: list(SszTypes.root())
        }
end
