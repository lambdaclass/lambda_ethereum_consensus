defmodule BeaconChain.StateTransition do
  alias LambdaEthereumConsensus.Engine.Execution

  def process_execution_payload(state, payload, config) do
    # Verify prev_randao
    # Verify timestamp
    # Verify the execution payload is valid
    Execution.notify_new_payload(payload)

    # Cache execution payload header
    Map.put(state, :latest_execution_payload_header, %SszTypes.ExecutionPayloadHeader{
      parent_hash: payload.parent_hash,
      fee_recipient: payload.fee_recipient,
      state_root: payload.state_root,
      receipts_root: payload.receipts_root,
      logs_bloom: payload.logs_bloom,
      prev_randao: payload.prev_randao,
      block_number: payload.block_number,
      gas_limit: payload.gas_limit,
      gas_used: payload.gas_used,
      timestamp: payload.timestamp,
      extra_data: payload.extra_data,
      base_fee_per_gas: payload.base_fee_per_gas,
      block_hash: payload.block_hash,
      transactions_root:
        with {:ok, root} <-
               Ssz.hash_list_tree_root_typed(
                 payload.transactions,
                 1_048_576,
                 SszTypes.Transaction,
                 config
               ) do
          root
        end,
      withdrawals_root:
        with {:ok, root} <-
               Ssz.hash_list_tree_root(
                 payload.withdrawals,
                 case config do
                   MainnetConfig -> 16
                   MinimalConfig -> 4
                 end,
                 config
               ) do
          root
        end
    })
  end
end
