defmodule Types.ExecutionPayloadHeader do
  @moduledoc """
  Struct definition for `ExecutionPayloadHeader`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

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
          parent_hash: Types.hash32(),
          fee_recipient: Types.execution_address(),
          state_root: Types.root(),
          receipts_root: Types.root(),
          # size BYTES_PER_LOGS_BLOOM 256
          logs_bloom: Types.bitvector(),
          prev_randao: Types.bytes32(),
          block_number: Types.uint64(),
          gas_limit: Types.uint64(),
          gas_used: Types.uint64(),
          timestamp: Types.uint64(),
          # size MAX_EXTRA_DATA_BYTES 32
          extra_data: Types.bitlist(),
          base_fee_per_gas: Types.uint256(),
          block_hash: Types.hash32(),
          transactions_root: Types.root(),
          withdrawals_root: Types.root()
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

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:parent_hash, {:bytes, 32}},
      {:fee_recipient, {:bytes, 20}},
      {:state_root, {:bytes, 32}},
      {:receipts_root, {:bytes, 32}},
      {:logs_bloom, {:bitvector, 256}},
      {:prev_randao, {:bytes, 32}},
      {:block_number, {:int, 64}},
      {:gas_limit, {:int, 64}},
      {:gas_used, {:int, 64}},
      {:timestamp, {:int, 64}},
      {:extra_data, {:bitlist, 32}},
      {:base_fee_per_gas, {:int, 256}},
      {:block_hash, {:bytes, 32}},
      {:transactions_root, {:bytes, 32}},
      {:withdrawals_root, {:bytes, 32}}
    ]
  end
end
