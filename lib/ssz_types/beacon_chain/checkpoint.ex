defmodule SszTypes.Checkpoint do
  @moduledoc """
  Struct definition for `Checkpoint`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :root,
    :epoch
  ]

  @schema %{epoch: :uint64, root: :bytes32}
  # [
  #   {:root, :bytes32},
  #   {:epoch, :uint64}
  # ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          epoch: SszTypes.epoch(),
          root: SszTypes.root()
        }

  def schema, do: @schema
end
