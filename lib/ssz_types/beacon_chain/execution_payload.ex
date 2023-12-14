defmodule SszTypes.ExecutionPayload do
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
    :withdrawals
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          parent_hash: SszTypes.hash32(),
          fee_recipient: SszTypes.execution_address(),
          state_root: SszTypes.root(),
          receipts_root: SszTypes.root(),
          # size BYTES_PER_LOGS_BLOOM 256
          logs_bloom: SszTypes.bitvector(),
          prev_randao: SszTypes.bytes32(),
          block_number: SszTypes.uint64(),
          gas_limit: SszTypes.uint64(),
          gas_used: SszTypes.uint64(),
          timestamp: SszTypes.uint64(),
          # size MAX_EXTRA_DATA_BYTES 32
          extra_data: SszTypes.bitlist(),
          base_fee_per_gas: SszTypes.uint256(),
          block_hash: SszTypes.hash32(),
          # size MAX_TRANSACTIONS_PER_PAYLOAD 1048576
          transactions: list(SszTypes.transaction()),
          # size MAX_TRANSACTIONS_PER_PAYLOAD 1048576
          withdrawals: list(SszTypes.Withdrawal.t())
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
      {:transactions, {:list, {:bytes, 8}, 1_048_576}},
      {:withdrawals, {:list, SszTypes.Withdrawal, 1_048_576}}
    ]
  end
end
