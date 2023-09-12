defmodule SszTypes.Eth1Data do
  @moduledoc """
  Struct definition for `Eth1Data`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :deposit_root,
    :deposit_count,
    :block_hash
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          deposit_root: SszTypes.root(),
          deposit_count: SszTypes.uint64(),
          block_hash: SszTypes.hash32()
        }
end
