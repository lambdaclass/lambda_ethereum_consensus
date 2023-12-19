defmodule Types.VoluntaryExit do
  @moduledoc """
  Struct definition for `VoluntaryExit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :epoch,
    :validator_index
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          epoch: Types.epoch(),
          validator_index: Types.validator_index()
        }
end
