defmodule Types.Eth1Data do
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
          deposit_root: Types.root(),
          deposit_count: Types.uint64(),
          block_hash: Types.hash32()
        }
end
