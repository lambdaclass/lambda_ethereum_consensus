defmodule LambdaEthereumConsensus.Execution.EngineApi.Behaviour do
  @moduledoc """
  Execution Layer Engine API behaviour
  """

  alias Types.ExecutionPayload

  @type forkchoice_state_v1 :: %{
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

  # @type forkchoice_updated_v3_result :: %{
  #         "payload_id" => binary(),
  #         "payload_status" => %{
  #           "latest_valid_hash" => binary() | nil,
  #           "status" => binary(),
  #           "validation_error" => binary() | nil
  #         }
  #       }

  @type forkchoice_updated_v3_result :: map()

  @callback exchange_capabilities() :: {:ok, any} | {:error, any}
  @callback new_payload(ExecutionPayload.t(), [Types.root()], Types.root()) ::
              {:ok, any} | {:error, any}
  @callback forkchoice_updated(forkchoice_state_v1(), payload_attributes_v3() | nil) ::
              {:ok, forkchoice_updated_v3_result()} | {:error, any}
  @callback get_block_header(nil | Types.uint64() | Types.root()) :: {:ok, any} | {:error, any}
  @callback get_deposit_logs(Range.t()) :: {:ok, list(any)} | {:error, any}
end
