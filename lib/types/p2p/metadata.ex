defmodule SszTypes.Metadata do
  @moduledoc """
  Struct definition for `Metadata`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :seq_number,
    :attnets,
    :syncnets
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          seq_number: SszTypes.uint64(),
          attnets: SszTypes.bitvector(),
          syncnets: SszTypes.bitvector()
        }
end
