defmodule Types.ExecutionPayloadDeneb do
  @moduledoc """
  Struct definition for `ExecutionPayload`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

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
    :withdrawals,
    :blob_gas_used,
    :excess_blob_gas
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          parent_hash: Types.hash32(),
          fee_recipient: Types.execution_address(),
          state_root: Types.root(),
          receipts_root: Types.root(),
          # size BYTES_PER_LOGS_BLOOM
          logs_bloom: binary(),
          prev_randao: Types.bytes32(),
          block_number: Types.uint64(),
          gas_limit: Types.uint64(),
          gas_used: Types.uint64(),
          timestamp: Types.uint64(),
          # size MAX_EXTRA_DATA_BYTES
          extra_data: binary(),
          base_fee_per_gas: Types.uint256(),
          block_hash: Types.hash32(),
          # size MAX_TRANSACTIONS_PER_PAYLOAD
          transactions: list(Types.transaction()),
          # size MAX_TRANSACTIONS_PER_PAYLOAD
          withdrawals: list(Types.Withdrawal.t()),
          blob_gas_used: Types.uint64(),
          excess_blob_gas: Types.uint64()
        }

  def encode(%__MODULE__{} = map) do
    Map.update!(map, :base_fee_per_gas, &Ssz.encode_u256/1)
  end

  def decode(%__MODULE__{} = map) do
    Map.update!(map, :base_fee_per_gas, &Ssz.decode_u256/1)
  end

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:parent_hash, TypeAliases.hash32()},
      {:fee_recipient, TypeAliases.execution_address()},
      {:state_root, TypeAliases.root()},
      {:receipts_root, TypeAliases.root()},
      {:logs_bloom, {:bytes, ChainSpec.get("BYTES_PER_LOGS_BLOOM")}},
      {:prev_randao, TypeAliases.bytes32()},
      {:block_number, TypeAliases.uint64()},
      {:gas_limit, TypeAliases.uint64()},
      {:gas_used, TypeAliases.uint64()},
      {:timestamp, TypeAliases.uint64()},
      {:extra_data, {:byte_list, ChainSpec.get("MAX_EXTRA_DATA_BYTES")}},
      {:base_fee_per_gas, TypeAliases.uint256()},
      {:block_hash, TypeAliases.hash32()},
      {:transactions, TypeAliases.transactions()},
      {:withdrawals, {:list, Types.Withdrawal, ChainSpec.get("MAX_TRANSACTIONS_PER_PAYLOAD")}},
      {:blob_gas_used, TypeAliases.uint64()},
      {:excess_blob_gas, TypeAliases.uint64()}
    ]
  end
end
