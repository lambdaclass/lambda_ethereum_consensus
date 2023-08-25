defmodule SszTypes.ExecutionPayloadHeaderMainnet do
  @moduledoc """
  Struct definition for `ExecutionPayloadHeaderCapellaMainnet`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :parent_hash,
    :fee_recipient,
    :state_root,
    :receipts_root,
    :logs_bloom,
    :prev_randao,
    :block_number,
    :gas_limit,
    :gas_used,
    :timestamp,
    :extra_data,
    :base_fee_per_gas,
    :block_hash,
    :transactions_root,
    :withdrawals_root
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          parent_hash: SszTypes.block_hash(),
          fee_recipient: SszTypes.address(),
          state_root: SszTypes.root(),
          receipts_root: SszTypes.root(),
          logs_bloom: SszTypes.gwei(),
          prev_randao: SszTypes.hash256(),
          block_number: SszTypes.uint64(),
          gas_limit: SszTypes.uint64(),
          gas_used: SszTypes.uint64(),
          timestamp: SszTypes.uint64(),
          extra_data: SszTypes.(),
          base_fee_per_gas: SszTypes.u256(),
          block_hash: SszTypes.block_hash(),
          transactions_root: SszTypes.root(),
          withdrawals_root: SszTypes.root()
        }
end
