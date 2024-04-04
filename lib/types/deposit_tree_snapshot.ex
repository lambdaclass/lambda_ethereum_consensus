defmodule Types.DepositTreeSnapshot do
  @moduledoc """
  Struct definition for a deposit snapshot, as defined in EIP-4881.
  """

  fields = [
    :finalized,
    :deposit_root,
    :deposit_count,
    :execution_block_hash,
    :execution_block_height
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          # Max size is 33
          finalized: list(Types.hash32()),
          deposit_root: Types.hash32(),
          deposit_count: Types.uint64(),
          execution_block_hash: Types.hash32(),
          execution_block_height: Types.uint64()
        }
end
