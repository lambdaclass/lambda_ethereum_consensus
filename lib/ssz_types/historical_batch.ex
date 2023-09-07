defmodule SszTypes.HistoricalBatch do
  @moduledoc """
  Struct definition for `HistoricalBatch`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :block_roots,
    :state_roots
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          block_roots: list(SszTypes.root()),
          state_roots: list(SszTypes.root())
        }
end
