defmodule Types.BeaconBlocksByRootRequest do
  @moduledoc """
  Struct definition for `BeaconBlocksByRootRequest`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :body
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          body: list(Types.root())
        }
end
