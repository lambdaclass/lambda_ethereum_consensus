defmodule SyncTestRunner do
  @moduledoc """
  Runner for Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/sync
  """

  use ExUnit.CaseTemplate
  use TestRunner

  alias LambdaEthereumConsensus.Execution.EngineApi

  @impl TestRunner
  def setup() do
    # Start this supervisor, necessary for post state tasks.
    start_link_supervised!({Task.Supervisor, name: StoreStatesSupervisor})
    :ok
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    original_engine_api_config = Application.fetch_env!(:lambda_ethereum_consensus, EngineApi)

    on_exit(fn ->
      Application.put_env(
        :lambda_ethereum_consensus,
        EngineApi,
        original_engine_api_config
      )
    end)

    Application.put_env(
      :lambda_ethereum_consensus,
      EngineApi,
      Keyword.put(original_engine_api_config, :implementation, SyncTestRunner.EngineApiMock)
    )

    {:ok, _pid} = SyncTestRunner.EngineApiMock.start_link([])

    ForkChoiceTestRunner.run_test_case(testcase)
  end
end

defmodule SyncTestRunner.EngineApiMock do
  @moduledoc """
  Mocked EngineApi for SyncTestRunner.
  """
  @behaviour LambdaEthereumConsensus.Execution.EngineApi.Behaviour

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{new_payload: %{}, forkchoice_updated: %{}} end, name: __MODULE__)
  end

  def add_new_payload_response(block_hash, payload_status) do
    Agent.update(__MODULE__, fn state ->
      Map.update!(state, :new_payload, fn new_payload ->
        Map.put(new_payload, block_hash, payload_status)
      end)
    end)
  end

  def add_forkchoice_updated_response(block_hash, payload_status) do
    Agent.update(__MODULE__, fn state ->
      Map.update!(state, :forkchoice_updated, fn forkchoice_updated ->
        Map.put(forkchoice_updated, block_hash, payload_status)
      end)
    end)
  end

  def new_payload(payload, _versioned_hashes, _parent_beacon_block_root) do
    Agent.get(__MODULE__, fn state ->
      payload_status = Map.get(state.new_payload, payload.block_hash)

      if payload_status do
        {:ok, payload_status}
      else
        {:error, "Unknown block hash when calling new_payload"}
      end
    end)
  end

  def forkchoice_updated(forkchoice_state, _payload_attributes) do
    Agent.get(__MODULE__, fn state ->
      payload_status = Map.get(state.forkchoice_updated, forkchoice_state.head_block_hash)

      if payload_status do
        {:ok, %{"payload_id" => nil, "payload_status" => payload_status}}
      else
        {:error, "Unknown block hash when calling forkchoice_updated"}
      end
    end)
  end

  def get_payload(_payload_id), do: raise("Not implemented")
  def exchange_capabilities(), do: raise("Not implemented")
  def get_block_header(_block_id), do: raise("Not implemented")
  def get_deposit_logs(_range), do: raise("Not implemented")
end
