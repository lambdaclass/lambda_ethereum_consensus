defmodule SszTypes.ForkData do
  @moduledoc """
  Struct definition for `ForkData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :current_version,
    :genesis_validators_root
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          current_version: SszTypes.h32(),
          genesis_validators_root: SszTypes.h256()
        }
end
