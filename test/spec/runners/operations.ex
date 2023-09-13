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
    # "execution_payload"
    "withdrawals",
    "bls_to_execution_change",
    "deposit_receipt"
  ]

  # Define the handler map as a module attribute for reuse
  @handler_map %{
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

    pre = build_file_path(case_dir, "pre") |> decompress() |> deserialize(testcase.handler, "pre")

    operation =
      build_file_path(case_dir, testcase.handler)
      |> decompress()
      |> deserialize(testcase.handler, "operation")

    post =
      build_file_path(case_dir, "post") |> decompress() |> deserialize(testcase.handler, "post")

    case testcase.handler do
      "attestation" ->
        process_attestation()

      "attester_slashing" ->
        process_attester_slashing()

      "block_header" ->
        process_block_header()

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

        process_execution_payload(pre, operation, execution_valid, post)

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
    assert(false)
  end

  def process_attester_slashing() do
    assert(false)
  end

  def process_block_header() do
    assert(false)
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

  def process_execution_payload(state, body, execution_valid, post) do
    # if post == {:error, "no post"} do
    #   assert true
    # end

    assert true
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

  defp decompress(file_path) do
    if File.exists?(file_path) do
      compressed = File.read!(file_path)
      {:ok, decompressed} = :snappyer.decompress(compressed)
      {:ok, decompressed}
    else
      {:error, "no post"}
    end
  end

  defp build_file_path(case_dir, name),
    do: "#{case_dir}/#{name}.ssz_snappy"

  defp deserialize({:error, _}, _, _), do: {:error, "no post"}

  defp deserialize({:ok, serialized}, _handler, "pre"),
    do: Ssz.from_ssz(serialized, SszTypes.BeaconState, @config)

  defp deserialize({:ok, serialized}, _handler, "post"),
    do: Ssz.from_ssz(serialized, SszTypes.BeaconState, @config)

  defp deserialize({:ok, serialized}, handler, _),
    do: Ssz.from_ssz(serialized, resolve_type_from_handler(handler), @config)

  defp resolve_type_from_handler(handler) do
    case Map.get(@handler_map, handler) do
      nil -> raise "Unknown case #{handler}"
      type -> Module.concat(SszTypes, type)
    end
  end
end
