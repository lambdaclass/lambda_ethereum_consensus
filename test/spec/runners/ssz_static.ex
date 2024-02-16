defmodule SszStaticTestRunner do
  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """
  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.Utils.Diff
  alias Ssz
  import Aja

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

    assert_ssz(schema, decompressed, expected_sanitized, sanitize_yaml, expected_root)
  end

  defp assert_ssz(
         schema,
         real_serialized,
         real_deserialized_sanitized,
         real_deserialized,
         _expected_root
       ) do
    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert Diff.diff(deserialized, real_deserialized_sanitized) == :unchanged

    {:ok, deserialized_old} = Ssz.from_ssz(real_serialized, schema)
    real_deserialized = to_struct_checked(deserialized_old, real_deserialized)

    assert Diff.diff(
             deserialized,
             SpecTestUtils.sanitize_ssz(from_deep_struct_to_map(real_deserialized), schema)
           ) == :unchanged

    {:ok, serialized} = SszEx.encode(real_deserialized_sanitized, schema)
    assert serialized == real_serialized

    {:ok, serialized_old} = Ssz.to_ssz(real_deserialized)
    assert Diff.diff(serialized, serialized_old) == :unchanged

    # TODO enable when hash_tree_root supports supports new schema types :byte_list
    # root = SszEx.hash_tree_root!(real_deserialized, schema)
    # assert root == expected_root
  end

  def from_deep_struct_to_map(%{} = map), do: convert(map)

  defp convert(vec(_) = actual) do
    Aja.Enum.to_list(actual) |> convert()
  end

  defp convert(data) when is_struct(data) do
    data |> Map.from_struct() |> convert()
  end

  defp convert(data) when is_map(data) do
    for {key, value} <- data, reduce: %{} do
      acc ->
        case key do
          :__meta__ ->
            acc

          other ->
            Map.put(acc, other, convert(value))
        end
    end
  end

  defp convert(data) when is_list(data) do
    for element <- data, reduce: [] do
      acc ->
        [convert(element) | acc]
    end
    |> Enum.reverse()
  end

  defp convert(other), do: other

  defp parse_type(%SpecTestCase{handler: handler}) do
    Module.concat(Types, handler)
  end

  defp to_struct_checked(actual, expected) when is_list(actual) and is_list(expected) do
    Stream.zip(actual, expected) |> Enum.map(fn {a, e} -> to_struct_checked(a, e) end)
  end

  defp to_struct_checked(vec(_) = actual, vec(_) = expected) do
    actual
    |> Aja.Enum.to_list()
    |> to_struct_checked(Aja.Enum.to_list(expected))
    |> Aja.Vector.new()
  end

  defp to_struct_checked(%name{} = actual, %{} = expected) do
    expected
    |> Stream.map(fn {k, v} -> {k, to_struct_checked(Map.get(actual, k), v)} end)
    |> Map.new()
    |> then(&struct!(name, &1))
  end

  defp to_struct_checked(_actual, expected), do: expected
end
