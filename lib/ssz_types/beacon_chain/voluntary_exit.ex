defmodule SszTypes.VoluntaryExit do
  @moduledoc """
  Struct definition for `VoluntaryExit`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :epoch,
    :validator_index
  ]

  @schema [
    %{epoch: %{type: :uint, size: 64}},
    %{validator_index: %{type: :uint, size: 64}}
  ]
  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          epoch: SszTypes.epoch(),
          validator_index: SszTypes.validator_index()
        }
  def schema, do: @schema
end
