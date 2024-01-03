defmodule Types.ExecutionPayload do
  @moduledoc """
  Struct definition for `ExecutionPayload`.
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
          parent_hash: Types.hash32(),
          fee_recipient: Types.execution_address(),
          state_root: Types.root(),
          receipts_root: Types.root(),
          logs_bloom: binary(),
          prev_randao: Types.bytes32(),
          block_number: Types.uint64(),
          gas_limit: Types.uint64(),
          gas_used: Types.uint64(),
          timestamp: Types.uint64(),
          extra_data: binary(),
          base_fee_per_gas: Types.uint256(),
          block_hash: Types.hash32(),
          transactions: list(Types.transaction()),
          withdrawals: list(Types.Withdrawal.t())
        }

  def encode(%__MODULE__{} = map) do
    Map.update!(map, :base_fee_per_gas, &Ssz.encode_u256/1)
  end

  def decode(%__MODULE__{} = map) do
    Map.update!(map, :base_fee_per_gas, &Ssz.decode_u256/1)
  end
end
