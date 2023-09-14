defmodule OperationsTestRunner do
  use ExUnit.CaseTemplate

  @moduledoc """
  Runner for operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/operations
  """

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    "attestation",
    "attester_slashing",
    "block_header",
    "deposit",
    "proposer_slashing",
    "voluntary_exit",
    "sync_aggregate",
    # "execution_payload",
    "withdrawals",
    "bls_to_execution_change",
    "deposit_receipt"
  ]

  # Map the operation-name to the associated operation-type
  @type_map %{
    "attestation" => "Attestation",
    "attester_slashing" => "AttesterSlashing",
    "block_header" => "BeaconBlock",
    "deposit" => "Deposit",
    "proposer_slashing" => "ProposerSlashing",
    "voluntary_exit" => "SignedVoluntaryExit",
    "sync_aggregate" => "SyncAggregate",
    "execution_payload" => "ExecutionPayload",
    "withdrawals" => "ExecutionPayload",
    "bls_to_execution_change" => "SignedBLSToExecutionChange",
    "deposit_receipt" => "DepositReceipt"
  }

  # Map the operation-name to the associated input name
  @name_map %{
    "attestation" => "attestation",
    "attester_slashing" => "attester_slashing",
    "block_header" => "block",
    "deposit" => "deposit",
    "proposer_slashing" => "proposer_slashing",
    "voluntary_exit" => "voluntary_exit",
    "sync_aggregate" => "sync_aggregate",
    "execution_payload" => "execution_payload",
    "withdrawals" => "execution_payload",
    "bls_to_execution_change" => "address_change",
    "deposit_receipt" => "deposit_receipt"
  }

  # Local test config
  @config MinimalConfig

  @doc """
  Returns true if the given testcase should be skipped
  """
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @doc """
  Runs the given test case.
  """
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)
    handler = testcase.handler

    {:ok, pre} = prepare_test(case_dir, handler, "pre")
    {:ok, operation} = prepare_test(case_dir, handler, resolve_name_from_handler(handler))
    {:ok, post} = prepare_test(case_dir, handler, "post")

    case testcase.handler do
      "attestation" ->
        assert_process_attestation(pre, operation, post)

      "attester_slashing" ->
        assert_process_attester_slashing(pre, operation, post)

      "block_header" ->
        assert_process_block_header(pre, operation, post)

      "deposit" ->
        assert_process_deposit(pre, operation, post)

      "proposer_slashing" ->
        assert_process_proposer_slashing(pre, operation, post)

      "voluntary_exit" ->
        assert_process_voluntary_exit(pre, operation, post)

      "sync_aggregate" ->
        assert_process_sync_aggregate(pre, operation, post)

      "execution_payload" ->
        %{execution_valid: execution_valid} =
          YamlElixir.read_from_file!(case_dir <> "/execution.yaml")
          |> SpecTestUtils.parse_yaml()

        assert_process_execution_payload(pre, operation, post, execution_valid)

      "withdrawals" ->
        assert_process_withdrawal(pre, operation, post)

      "bls_to_execution_change" ->
        assert_process_bls_to_execution_change(pre, operation, post)

      "deposit_receipt" ->
        assert_process_deposit_receipt(pre, operation, post)

      handler ->
        raise "Unknown case: #{handler}"
    end
  end

  def assert_process_attestation(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_attester_slashing(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_block_header(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_deposit(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_proposer_slashing(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_voluntary_exit(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_sync_aggregate(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_execution_payload(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_withdrawal(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_bls_to_execution_change(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  def assert_process_deposit_receipt(_pre, _operation, _post, _data \\ "none") do
    # TODO
  end

  @doc """
  Prepares the data for the tests: build_path() |> decompress() |> deserialize()
  """
  def prepare_test(case_dir, handler, name) do
    build_file_path(case_dir, name) |> decompress() |> deserialize(handler, name)
  end

  @doc """
  Snappy decompression of the files
  """
  def decompress(file_path) do
    if File.exists?(file_path) do
      compressed = File.read!(file_path)
      {:ok, decompressed} = :snappyer.decompress(compressed)
      {:ok, decompressed}
    else
      {:ok, "no post"}
    end
  end

  @doc """
  Deserialization of the files
  """
  def deserialize({:ok, "no post"}, _, _), do: {:ok, "no post"}

  def deserialize({:ok, serialized}, _handler, "pre") do
    Ssz.from_ssz(serialized, SszTypes.BeaconState, @config)
  end

  def deserialize({:ok, serialized}, _handler, "post") do
    Ssz.from_ssz(serialized, SszTypes.BeaconState, @config)
  end

  def deserialize({:ok, serialized}, handler, _) do
    Ssz.from_ssz(serialized, resolve_type_from_handler(handler), @config)
  end

  def build_file_path(case_dir, name) do
    "#{case_dir}/#{name}.ssz_snappy"
  end

  @doc """
  Each handler has associated types, hence we resolve each type that has to be used from each handler
  """
  def resolve_type_from_handler(handler) do
    case Map.get(@type_map, handler) do
      nil -> raise "Unknown case #{handler}"
      type -> Module.concat(SszTypes, type)
    end
  end

  @doc """
  Each handler has associated name, hence we resolve each name that has to be used from each handler
  """
  def resolve_name_from_handler(handler) do
    case Map.get(@name_map, handler) do
      nil -> raise "Unknown case #{handler}"
      name -> name
    end
  end
end
