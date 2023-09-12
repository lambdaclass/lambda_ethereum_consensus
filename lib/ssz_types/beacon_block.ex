defmodule SszTypes.BeaconBlock do
  @moduledoc """
  Struct definition for `BeaconBlock`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :slot,
    :proposer_index,
    :parent_root,
    :state_root,
    :body
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          slot: SszTypes.slot(),
          proposer_index: SszTypes.validator_index(),
          parent_root: SszTypes.root(),
          state_root: SszTypes.root(),
          body: SszTypes.BeaconBlockBody.t()
        }
end
