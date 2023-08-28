defmodule SszTypes.ExecutionPayloadMinimal do
  @moduledoc """
  Struct definition for `ExecutionPayloadCapellaMinimal`.
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
    :transactions,
    :withdrawals
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          parent_hash: SszTypes.hash32(),
          fee_recipient: SszTypes.execution_address(),
          state_root: SszTypes.root(),
          receipts_root: SszTypes.root(),
          logs_bloom: SszTypes.list(),
          prev_randao: SszTypes.bytes32(),
          block_number: SszTypes.uint64(),
          gas_limit: SszTypes.uint64(),
          gas_used: SszTypes.uint64(),
          timestamp: SszTypes.uint64(),
          extra_data: SszTypes.list(),
          base_fee_per_gas: SszTypes.uint256(),
          block_hash: SszTypes.hash32(),
          transactions: list(SszTypes.transaction()),
          withdrawals: list(SszTypes.Withdrawal)
        }
end
