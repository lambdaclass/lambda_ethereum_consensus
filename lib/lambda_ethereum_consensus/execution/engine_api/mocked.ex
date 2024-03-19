defmodule LambdaEthereumConsensus.Execution.EngineApi.Mocked do
  @moduledoc """
  Mocked Execution Layer Engine API methods
  """
  alias Types.ExecutionPayload
  alias Types.ExecutionPayload

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  @spec exchange_capabilities() :: {:ok, any} | {:error, any}
  def exchange_capabilities do
    {:ok, ["engine_newPayloadV2", "engine_newPayloadV3"]}
  end

  @spec new_payload(ExecutionPayload.t(), [list(Types.root())], Types.root()) ::
          {:ok, any} | {:error, any}
  def new_payload(_execution_payload, _versioned_hashes, _parent_beacon_block_root) do
    {:ok, %{"status" => "VALID"}}
  end

  @spec forkchoice_updated(map, map | any) :: {:ok, any} | {:error, any}
  def forkchoice_updated(_forkchoice_state, _payload_attributes) do
    {:ok, %{"payload_id" => nil, "payload_status" => %{"status" => "VALID"}}}
  end
end
