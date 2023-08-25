defmodule SszTypes.ExecutionPayloadMainnet do
  @moduledoc """
  Struct definition for `ExecutionPayloadHeaderCapellaMinimal`.
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
          parent_hash: SszTypes.gwei(),
          fee_recipient: SszTypes.gwei(),
          state_root: SszTypes.gwei(),
          receipts_root: SszTypes.gwei(),
          logs_bloom: SszTypes.gwei(),
          prev_randao: SszTypes.gwei(),
          block_number: SszTypes.gwei(),
          gas_limit: SszTypes.gwei(),
          gas_used: SszTypes.gwei(),
          timestamp: SszTypes.gwei(),
          extra_data: SszTypes.gwei(),
          base_fee_per_gas: SszTypes.gwei(),
          block_hash: SszTypes.gwei(),
          transactions: SszTypes.gwei(),
          withdrawals: SszTypes.gwei()
        }
end
