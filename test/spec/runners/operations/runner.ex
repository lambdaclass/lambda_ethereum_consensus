defmodule OperationsTestRunner do
  use ExUnit.CaseTemplate
  use TestRunner

  @moduledoc """
  Runner for Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/operations
  """

  # Remove handler from here once you implement the corresponding functions
  # "deposit_receipt" handler is not yet implemented
  @disabled_handlers [
    "attestation",
    "attester_slashing",
    "block_header",
    "deposit",
    "proposer_slashing",
    "voluntary_exit",
    "sync_aggregate",
    "execution_payload",
    "withdrawals",
    "bls_to_execution_change"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{} = testcase) do
    Enum.member?(@disabled_handlers, testcase.handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)
    handler = testcase.handler

    pre =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/pre.ssz_snappy",
        SszTypes.BeaconState
      )

    operation =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <>
          "/" <> OperationsTestUtils.resolve_name_from_handler(handler) <> ".ssz_snappy",
        OperationsTestUtils.resolve_type_from_handler(handler)
      )

    {:ok, post} =
      SpecTestUtils.read_ssz_from_file(
        case_dir <> "/post.ssz_snappy",
        SszTypes.BeaconState
      )

    handle_case(testcase.handler, pre, operation, post, case_dir)
  end

  def handle_case("attestation", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_attestation(pre, operation, post)

  def handle_case("attester_slashing", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_attester_slashing(pre, operation, post)

  def handle_case("block_header", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_block_header(pre, operation, post)

  def handle_case("deposit", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_deposit(pre, operation, post)

  def handle_case("proposer_slashing", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_proposer_slashing(pre, operation, post)

  def handle_case("voluntary_exit", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_voluntary_exit(pre, operation, post)

  def handle_case("sync_aggregate", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_sync_aggregate(pre, operation, post)

  def handle_case("execution_payload", pre, operation, post, case_dir) do
    %{execution_valid: execution_valid} =
      YamlElixir.read_from_file!(case_dir <> "/execution.yaml")
      |> SpecTestUtils.parse_yaml()

    OperationsTestAssert.assert_process_execution_payload(pre, operation, post, execution_valid)
  end

  def handle_case("withdrawals", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_withdrawal(pre, operation, post)

  def handle_case("bls_to_execution_change", pre, operation, post, _case_dir),
    do: OperationsTestAssert.assert_process_bls_to_execution_change(pre, operation, post)
end
