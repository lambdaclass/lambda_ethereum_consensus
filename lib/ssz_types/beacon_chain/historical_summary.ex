defmodule SszTypes.HistoricalSummary do
  @moduledoc """
  Struct definition for `HistoricalSummary`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :block_summary_root,
    :state_summary_root
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          block_summary_root: SszTypes.root(),
          state_summary_root: SszTypes.root()
        }
end
