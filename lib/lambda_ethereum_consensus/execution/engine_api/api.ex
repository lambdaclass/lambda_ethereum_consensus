defmodule LambdaEthereumConsensus.Execution.EngineApi.Api do
  @moduledoc """
  Execution Layer Engine API methods
  """
  @behaviour LambdaEthereumConsensus.Execution.EngineApi.Behaviour

  alias LambdaEthereumConsensus.Execution.Auth
  alias LambdaEthereumConsensus.Execution.EngineApi
  alias LambdaEthereumConsensus.Execution.RPC

  @supported_methods ["engine_newPayloadV3", "engine_forkchoiceUpdatedV3"]

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  def exchange_capabilities do
    call("engine_exchangeCapabilities", [@supported_methods])
  end

  def new_payload(execution_payload, versioned_hashes, parent_beacon_block_root) do
    call(
      "engine_newPayloadV3",
      RPC.normalize([execution_payload, versioned_hashes, parent_beacon_block_root])
    )
  end

  def get_payload(payload_id) do
    call("engine_getPayloadV3", [payload_id])
  end

  def forkchoice_updated(forkchoice_state, payload_attributes) do
    call("engine_forkchoiceUpdatedV3", RPC.normalize([forkchoice_state, payload_attributes]))
  end

  # TODO: this is not part of the Engine API. Should we move it elsewhere?
  def get_block_header(nil), do: call("eth_getBlockByNumber", ["latest", false])

  def get_block_header(block_id) when is_integer(block_id),
    do: call("eth_getBlockByNumber", [RPC.normalize(block_id), false])

  def get_block_header(block_id) when is_binary(block_id),
    do: call("eth_getBlockByHash", [RPC.normalize(block_id), false])

  def get_deposit_logs(from_block..to_block) do
    deposit_contract = ChainSpec.get("DEPOSIT_CONTRACT_ADDRESS")

    # `keccak("DepositEvent(bytes,bytes,bytes,bytes,bytes)")`
    deposit_event_topic = "0x649bbc62d0e31342afea4e5cd82d4049e7e1ee912fc0889aa790803be39038c5"

    filter = %{
      "address" => RPC.normalize(deposit_contract),
      "fromBlock" => RPC.normalize(from_block),
      "toBlock" => RPC.normalize(to_block),
      "topics" => [deposit_event_topic]
    }

    call("eth_getLogs", [filter])
  end

  defp call(method, params) do
    config = Application.fetch_env!(:lambda_ethereum_consensus, EngineApi)

    endpoint = Keyword.fetch!(config, :endpoint)
    version = Keyword.fetch!(config, :version)
    jwt_secret = Keyword.fetch!(config, :jwt_secret)

    jwt = Auth.generate_token(jwt_secret)
    RPC.rpc_call(endpoint, jwt, version, method, params)
  end
end
