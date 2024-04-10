defmodule LambdaEthereumConsensus.Execution.EngineApi.Mocked do
  @moduledoc """
  Mocked Execution Layer Engine API methods
  """
  @behaviour LambdaEthereumConsensus.Execution.EngineApi.Behaviour

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  def exchange_capabilities do
    {:ok, ["engine_newPayloadV2", "engine_newPayloadV3"]}
  end

  def new_payload(_execution_payload, _versioned_hashes, _parent_beacon_block_root) do
    {:ok, %{"status" => "VALID"}}
  end

  def forkchoice_updated(_forkchoice_state, _payload_attributes) do
    {:ok, %{"payload_id" => nil, "payload_status" => %{"status" => "VALID"}}}
  end

  def get_payload(_payload), do: raise("not implemented")

  # TODO: should we mock this too?
  def get_block_header(_block_id), do: raise("not supported")

  # TODO: should we mock this too?
  def get_deposit_logs(_range), do: raise("not supported")
end
