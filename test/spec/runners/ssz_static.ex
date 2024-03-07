defmodule SszStaticTestRunner do
  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """
  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.Utils.Diff
  alias Ssz

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

    sanitize_yaml =
      YamlElixir.read_from_file!(case_dir <> "/value.yaml")
      |> SpecTestUtils.sanitize_yaml()

    expected_sanitized =
      SpecTestUtils.sanitize_ssz(sanitize_yaml, schema)

    %{"root" => expected_root} = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")
    expected_root = expected_root |> SpecTestUtils.sanitize_yaml()

    assert_ssz(schema, decompressed, expected_sanitized, expected_root)
  end

  defp assert_ssz(
         schema,
         real_serialized,
         real_deserialized,
         expected_root
       ) do
    {:ok, deserialized_by_ssz_ex} = SszEx.decode(real_serialized, schema)
    assert Diff.diff(deserialized_by_ssz_ex, real_deserialized) == :unchanged

    {:ok, deserialized_by_nif} = Ssz.from_ssz(real_serialized, schema)
    assert Diff.diff(deserialized_by_ssz_ex, deserialized_by_nif) == :unchanged

    {:ok, serialized_by_ssz_ex} = SszEx.encode(real_deserialized, schema)
    assert serialized_by_ssz_ex == real_serialized

    {:ok, serialized_by_nif} = Ssz.to_ssz(real_deserialized)
    assert Diff.diff(serialized_by_ssz_ex, serialized_by_nif) == :unchanged

    {:ok, root_by_nif} = Ssz.hash_tree_root(real_deserialized)
    assert root_by_nif == expected_root

    {:ok, root_by_ssz_ex} = SszEx.hash_tree_root(real_deserialized, schema)
    assert root_by_ssz_ex == expected_root
  end

  defp parse_type(%SpecTestCase{handler: handler}) do
    Module.concat(Types, handler)
  end
end
