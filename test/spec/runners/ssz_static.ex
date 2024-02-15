defmodule SszStaticTestRunner do
  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """
  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.Utils.Diff

  use ExUnit.CaseTemplate
  use TestRunner

  @disabled [
    # "DepositData",
    # "DepositMessage",
    # "Eth1Data",
    # "ProposerSlashing",
    # "SignedBeaconBlockHeader",
    # "SignedVoluntaryExit",
    # "Validator",
    # "VoluntaryExit",
    # "Attestation",
    # "AttestationData",
    # "BLSToExecutionChange",
    # "BeaconBlockHeader",
    # "Checkpoint",
    # "Deposit",
    # "SignedBLSToExecutionChange",
    # "SigningData",
    # "SyncCommittee",
    # "Withdrawal",
    # "AttesterSlashing",
    # "HistoricalSummary",
    # "PendingAttestation",
    # "Fork",
    # "ForkData",
    # "HistoricalBatch",
    # "IndexedAttestation",
    # "ExecutionPayload",
    # "ExecutionPayloadHeader",
    # "SignedBeaconBlock",
    # "SyncAggregate",
    # "AggregateAndProof",
    # "BeaconBlock",
    # "BeaconBlockBody",
    # "BeaconState",
    # "SignedAggregateAndProof",
    # -- not defined yet
    "LightClientBootstrap",
    "LightClientOptimisticUpdate",
    "LightClientUpdate",
    "Eth1Block",
    "PowBlock",
    "SignedContributionAndProof",
    "SignedData",
    "SyncAggregatorSelectionData",
    "SyncCommitteeContribution",
    "ContributionAndProof",
    "LightClientFinalityUpdate",
    "LightClientHeader",
    "SyncCommitteeMessage"
  ]

  @impl TestRunner
  def skip?(%SpecTestCase{fork: fork, handler: handler}) do
    fork != "capella" or Enum.member?(@disabled, handler)
  end

  @impl TestRunner
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    schema = parse_type(testcase)

    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    expected =
      YamlElixir.read_from_file!(case_dir <> "/value.yaml")
      |> SpecTestUtils.sanitize_yaml()
      |> SpecTestUtils.sanitize_ssz(schema)

    %{"root" => expected_root} = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")
    expected_root = expected_root |> SpecTestUtils.sanitize_yaml()

    assert_ssz(schema, decompressed, expected, expected_root)
  end

  defp assert_ssz(schema, real_serialized, real_deserialized, expected_root) do
    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert Diff.diff(deserialized, real_deserialized) == :unchanged
    {:ok, serialized} = SszEx.encode(real_deserialized, schema)
    assert serialized == real_serialized

    root = SszEx.hash_tree_root!(real_deserialized, schema)
    assert root == expected_root
  end

  defp parse_type(%SpecTestCase{handler: handler}) do
    Module.concat(Types, handler)
  end
end
