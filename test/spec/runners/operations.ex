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

    pre = decompress(case_dir, "pre") |> deserialize(testcase.handler)
    operation = decompress(case_dir, testcase.handler) |> deserialize(testcase.handler)
    post = decompress(case_dir, "post") |> deserialize(testcase.handler)

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
    IO.puts(state)
    IO.puts(body)
    IO.puts(execution_valid)
    IO.puts(post)
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

  defp decompress(case_dir, name) do
    compressed = File.read!(case_dir <> "/#{name}.ssz_snappy")
    {:ok, decompressed} = :snappyer.decompress(compressed)
    decompressed
  end

  defp deserialize(serialized, handler) do
    IO.puts("serialized:")
    IO.inspect(serialized)
    IO.puts("handler:")
    IO.inspect(handler)

    {:ok, deserialized} =
      Ssz.from_ssz(
        serialized,
        Module.concat(
          SszTypes,
          case handler do
            "attestation" -> "Attestation"
            "attester_slashing" -> "AttesterSlashing"
            "block_header" -> "BeaconBlock"
            "deposit" -> "Deposit"
            "proposer_slashing" -> "ProposerSlashing"
            "voluntary_exit" -> "SignedVoluntaryExit"
            "sync_aggregate" -> "SyncAggregate"
            "execution_payload" -> "BeaconBlockBody"
            "withdrawals" -> "ExecutionPayload"
            "bls_to_execution_change" -> "SignedBLSToExecutionChange"
            "deposit_receipt" -> "DepositReceipt"
            _ -> raise "Unknown case #{handler}"
          end
        ),
        MinimalConfig
      )

    deserialized
  end

  defp assert_operation() do
  end
end
