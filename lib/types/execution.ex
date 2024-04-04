defmodule Types.Execution do
  @type forkchoice_state_v3 :: %{
          finalized_block_hash: Types.hash32(),
          head_block_hash: Types.hash32(),
          safe_block_hash: Types.hash32()
        }

  @type payload_attributes_v3 :: %{
          timestamp: Types.uint64(),
          prev_randao: Types.bytes32(),
          suggested_fee_recipient: Types.execution_address(),
          withdrawals: list(Types.Withdrawal.t()),
          parent_beacon_block_root: Types.root()
        }

  @type forkchoice_updated_v3_result :: %{
          payload_id: any,
          payload_status: %{
            latest_valid_hash: nil,
            status: any,
            validation_error: nil
          }
        }
end
