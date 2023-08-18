defmodule SszTypes.Fork do
  @moduledoc """
  Struct definition for `Fork`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :previous_version,
    :current_version,
    :epoch
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          previous_version: SszTypes.h32(),
          current_version: SszTypes.h32(),
          epoch: SszTypes.u64()
        }
end
