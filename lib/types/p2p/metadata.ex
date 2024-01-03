defmodule Types.Metadata do
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
          seq_number: Types.uint64(),
          attnets: Types.bitvector(),
          syncnets: Types.bitvector()
        }
end
