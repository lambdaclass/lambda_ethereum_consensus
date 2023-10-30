defmodule OperationsTestRunner do
  @moduledoc """
  Runner for Operations test cases. See: https://github.com/ethereum/consensus-specs/tree/dev/tests/formats/operations
  """

  use ExUnit.CaseTemplate
  use TestRunner

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
    # "execution_payload",
    "withdrawals",
    "bls_to_execution_change"
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
    "bls_to_execution_change" => "SignedBLSToExecutionChange"
    # "deposit_receipt" => "DepositReceipt" Not yet implemented
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
    "bls_to_execution_change" => "address_change"
    # "deposit_receipt" => "deposit_receipt" Not yet implemented
  }

  @impl TestRunner
  def skip?(%SpecTestCase{fork: fork, handler: handler}) do
    fork != "capella" or Enum.member?(@disabled_handlers, handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{handler: handler} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    pre =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <> "/pre.ssz_snappy",
        SszTypes.BeaconState
      )

    operation =
      SpecTestUtils.read_ssz_from_file!(
        case_dir <>
          "/" <> SpecTestUtils.resolve_name_from_handler(handler, @name_map) <> ".ssz_snappy",
        SpecTestUtils.resolve_type_from_handler(handler, @type_map)
      )

    post =
      SpecTestUtils.read_ssz_from_optional_file!(
        case_dir <> "/post.ssz_snappy",
        SszTypes.BeaconState
      )

    handle_case(testcase.handler, pre, operation, post, case_dir)
  end

  defp handle_case("execution_payload", _pre, _operation, _post, case_dir) do
    %{execution_valid: _execution_valid} =
      YamlElixir.read_from_file!(case_dir <> "/execution.yaml")
      |> SpecTestUtils.sanitize_yaml()

    assert true
  end
end
