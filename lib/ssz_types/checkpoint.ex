defmodule SszTypes.Checkpoint do
  @moduledoc """
  Struct definition for `Checkpoint`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :root,
    :epoch
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          root: SszTypes.h256(),
          epoch: SszTypes.u64()
        }
end
