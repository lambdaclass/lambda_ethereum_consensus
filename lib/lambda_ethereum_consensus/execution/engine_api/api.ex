defmodule LambdaEthereumConsensus.Execution.EngineApi.Api do
  @moduledoc """
  Execution Layer Engine API methods
  """
  @behaviour LambdaEthereumConsensus.Execution.EngineApi.Behaviour

  alias LambdaEthereumConsensus.Execution.Auth
  alias LambdaEthereumConsensus.Execution.EngineApi
  alias LambdaEthereumConsensus.Execution.RPC

  @supported_methods ["engine_newPayloadV4", "engine_newPayloadV3", "engine_forkchoiceUpdatedV3"]

  @doc """
  Using this method Execution and consensus layer client software may
  exchange with a list of supported Engine API methods.
  """
  def exchange_capabilities() do
    call("engine_exchangeCapabilities", [@supported_methods])
  end

  def new_payload(execution_payload, versioned_hashes, parent_beacon_block_root) do
    call(
      "engine_newPayloadV3",
      RPC.normalize([execution_payload, versioned_hashes, parent_beacon_block_root])
    )
  end

  def new_payload(
        execution_payload,
        versioned_hashes,
        parent_beacon_block_root,
        execution_requests
      ) do
    encoded_requests = encode_execution_requests(execution_requests)

    call(
      "engine_newPayloadV4",
      RPC.normalize([execution_payload, versioned_hashes, parent_beacon_block_root]) ++
        [encoded_requests]
    )
  end

  # Per EIP-7685: each non-empty request list is serialized as type_byte ++ ssz_list,
  # then hex-encoded. Empty lists are omitted.
  defp encode_execution_requests(%Types.ExecutionRequests{
         deposits: deposits,
         withdrawals: withdrawals,
         consolidations: consolidations
       }) do
    [
      {0, deposits,
       {:list, Types.DepositRequest, ChainSpec.get("MAX_DEPOSIT_REQUESTS_PER_PAYLOAD")}},
      {1, withdrawals,
       {:list, Types.WithdrawalRequest, ChainSpec.get("MAX_WITHDRAWAL_REQUESTS_PER_PAYLOAD")}},
      {2, consolidations,
       {:list, Types.ConsolidationRequest,
        ChainSpec.get("MAX_CONSOLIDATION_REQUESTS_PER_PAYLOAD")}}
    ]
    |> Enum.reject(fn {_type, list, _schema} -> Enum.empty?(list) end)
    |> Enum.map(fn {type_id, list, schema} ->
      {:ok, encoded} = SszEx.encode(list, schema)
      RPC.encode_binary(<<type_id>> <> encoded)
    end)
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

  defp call(method, params) do
    config = Application.fetch_env!(:lambda_ethereum_consensus, EngineApi)

    endpoint = Keyword.fetch!(config, :endpoint)
    version = Keyword.fetch!(config, :version)
    jwt_secret = Keyword.fetch!(config, :jwt_secret)

    jwt = Auth.generate_token(jwt_secret)
    RPC.rpc_call(endpoint, jwt, version, method, params)
  end
end
