defmodule OperationsTestRunner do
  use ExUnit.CaseTemplate

  @moduledoc """
  Runner for operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/operations
  """

  # Remove handler from here once you implement the corresponding functions
  @disabled_handlers [
    # "attestation",
    # "attester_slashing",
    # "block_header",
    "deposit",
    "proposer_slashing",
    "voluntary_exit",
    "sync_aggregate",
    "execution_payload",
    "withdrawals",
    "bls_to_execution_change",
    "deposit_receipt"
  ]

  # Map the operation-name to the associated type
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
    "execution_payload" => "body",
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
    IO.puts("✅ pre")
    {:ok, operation} = prepare_test(case_dir, handler, resolve_name_from_handler(handler))
    IO.puts("✅ operation")
    IO.inspect(operation)
    {:ok, post} = prepare_test(case_dir, handler, "post")
    IO.puts("✅ post")

    case testcase.handler do
      "attestation" ->
        process_attestation()

      "attester_slashing" ->
        process_attester_slashing()

      "block_header" ->
        process_block_header(pre, operation, post)

      "deposit" ->
        process_deposit()

      "proposer_slashing" ->
        process_proposer_slashing()

      "voluntary_exit" ->
        process_voluntary_exit()

      "sync_aggregate" ->
        process_sync_aggregate()

      "execution_payload" ->
        %{execution_valid: execution_valid} =
          YamlElixir.read_from_file!(case_dir <> "/execution.yaml")
          |> SpecTestUtils.parse_yaml()

        process_execution_payload(pre, operation, post, execution_valid)

      "withdrawals" ->
        process_withdrawal()

      "bls_to_execution_change" ->
        process_bls_to_execution_change()

      "deposit_receipt" ->
        process_deposit_receipt()

      handler ->
        raise "Unknown case: #{handler}"
    end
  end

  def process_attestation() do
    assert true
  end

  def process_attester_slashing() do
    assert true
  end

  def process_block_header(pre, operation, post) do
    assert true
    # debug_method(pre, operation, post)
  end

  def process_deposit() do
    assert(false)
  end

  def process_proposer_slashing() do
    assert(false)
  end

  def process_voluntary_exit() do
    assert(false)
  end

  def process_sync_aggregate() do
    assert(false)
  end

  def process_execution_payload(
        pre,
        operation,
        post,
        execution_valid
      ) do
    assert true
    # debug_method(pre, operation, post, execution_valid)
  end

  def process_withdrawal() do
    assert(false)
  end

  def process_bls_to_execution_change() do
    assert(false)
  end

  def process_deposit_receipt() do
    assert(false)
  end

  def debug_method(pre, operation, post, data \\ "none") do
    IO.puts("pre:")
    IO.inspect(pre)
    IO.puts("operation:")
    IO.inspect(operation)
    IO.puts("post:")
    IO.inspect(post)
    IO.puts("data:")
    IO.inspect(data)
  end

  @doc """
  Prepares the data for the tests: build_path() |> decompress() |> deserialize()
  """
  def prepare_test(case_dir, handler, name) do
    build_file_path(case_dir, name) |> decompress() |> deserialize(handler, name)
  end

  @doc """
  Snappy decompression of the .ssz_snapp files
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
    IO.puts("pre before deserializing BeaconState")
    Ssz.from_ssz(serialized, SszTypes.BeaconState, @config)
  end

  def deserialize({:ok, serialized}, _handler, "post") do
    IO.puts("post before deserializing BeaconState")
    Ssz.from_ssz(serialized, SszTypes.BeaconState, @config)
  end

  def deserialize({:ok, serialized}, handler, _) do
    IO.puts("#{handler} before deserializing #{resolve_type_from_handler(handler)}")
    Ssz.from_ssz(serialized, resolve_type_from_handler(handler), @config)
  end

  def build_file_path(case_dir, name) do
    IO.puts("file path: #{case_dir}/#{name}.ssz_snappy")
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

  def resolve_name_from_handler(handler) do
    case Map.get(@name_map, handler) do
      nil -> raise "Unknown case #{handler}"
      name -> name
    end
  end
end
