defmodule SszTypes.StatusMessage do
  @moduledoc """
  Struct definition for `StatusMessage`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :fork_digest,
    :finalized_root,
    :finalized_epoch,
    :head_root,
    :head_slot
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          fork_digest: SszTypes.fork_digest(),
          finalized_root: SszTypes.root(),
          finalized_epoch: SszTypes.epoch(),
          head_root: SszTypes.root(),
          head_slot: SszTypes.slot()
        }
end
