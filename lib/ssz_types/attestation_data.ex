defmodule SszTypes.AttestationData do
  @moduledoc """
  Struct definition for `AttestationData`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :slot,
    :index,
    :beacon_block_root,
    :source,
    :target
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          slot: SszTypes.u64(),
          index: SszTypes.u64(),
          beacon_block_root: SszTypes.h256(),
          source: SszTypes.Checkpoint.t(),
          target: SszTypes.Checkpoint.t()
        }
end
