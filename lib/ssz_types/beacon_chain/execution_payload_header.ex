defmodule SszTypes.ExecutionPayloadHeader do
  @moduledoc """
  Struct definition for `ExecutionPayloadHeader`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  @default_execution_payload_header %{
    parent_hash: <<0::256>>,
    fee_recipient: <<0::160>>,
    state_root: <<0::256>>,
    receipts_root: <<0::256>>,
    logs_bloom: <<0::2048>>,
    prev_randao: <<0::256>>,
    block_number: 0,
    gas_limit: 0,
    gas_used: 0,
    timestamp: 0,
    extra_data: "",
    base_fee_per_gas: 0,
    block_hash: <<0::256>>,
    transactions_root: <<0::256>>,
    withdrawals_root: <<0::256>>
  }

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
          parent_hash: SszTypes.hash32(),
          fee_recipient: SszTypes.execution_address(),
          state_root: SszTypes.root(),
          receipts_root: SszTypes.root(),
          logs_bloom: binary(),
          prev_randao: SszTypes.bytes32(),
          block_number: SszTypes.uint64(),
          gas_limit: SszTypes.uint64(),
          gas_used: SszTypes.uint64(),
          timestamp: SszTypes.uint64(),
          extra_data: binary(),
          base_fee_per_gas: SszTypes.uint256(),
          block_hash: SszTypes.hash32(),
          transactions_root: SszTypes.root(),
          withdrawals_root: SszTypes.root()
        }

  def encode(%__MODULE__{} = map) do
    Map.update!(map, :base_fee_per_gas, &Ssz.encode_u256/1)
  end

  def decode(%__MODULE__{} = map) do
    Map.update!(map, :base_fee_per_gas, &Ssz.decode_u256/1)
  end

  def default do
    @default_execution_payload_header
  end
end
