defmodule Types.ForkData do
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
          current_version: Types.version(),
          genesis_validators_root: Types.root()
        }
end
