defmodule OperationsTestFunctions do
  use ExUnit.Case

  def test_process_execution_payload(state, payload, execution_valid) do
    # Verify prev_randao
    # Verify timestamp

    # We should verify the execution payload is valid, during operations
    # spec-tests the execution engine response is mocked and passed as a dict
    assert execution_valid

    # Cache execution payload header
    Map.put(
      state,
      :latest_execution_payload_header,
      %SszTypes.ExecutionPayloadHeader{
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
          Ssz.hash_list_tree_root_typed(
            payload.transactions,
            1_048_576,
            SszTypes.Transaction,
            MinimalConfig
          ),
        withdrawals_root:
          Ssz.hash_list_tree_root(
            payload.withdrawals,
            16,
            MinimalConfig
          )
      }
    )
  end
end
