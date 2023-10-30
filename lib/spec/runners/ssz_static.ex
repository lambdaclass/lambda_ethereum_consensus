defmodule SszStaticTestRunner do
  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """

  use ExUnit.CaseTemplate
  use TestRunner

  @disabled [
    "ContributionAndProof",
    "Eth1Block",
    "LightClientBootstrap",
    "LightClientFinalityUpdate",
    "LightClientHeader",
    "LightClientOptimisticUpdate",
    "LightClientUpdate",
    "PowBlock",
    "SignedContributionAndProof",
    "SyncAggregatorSelectionData",
    "SyncCommitteeContribution",
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

    %{"root" => expected_root} = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")
    expected_root = expected_root |> SpecTestUtils.sanitize_yaml()

    assert_ssz(schema, decompressed, expected, expected_root)
  end

  defp assert_ssz(schema, real_serialized, real_deserialized, expected_root) do
    {:ok, deserialized} = Ssz.from_ssz(real_serialized, schema)
    real_deserialized = to_struct_checked(deserialized, real_deserialized)

    assert deserialized == real_deserialized

    {:ok, serialized} = Ssz.to_ssz(real_deserialized)
    assert serialized == real_serialized

    {:ok, root} = Ssz.hash_tree_root(real_deserialized)
    assert root == expected_root
  end

  defp to_struct_checked(actual, expected) when is_list(actual) and is_list(expected) do
    Stream.zip(actual, expected)
    |> Enum.map(fn {a, e} -> to_struct_checked(a, e) end)
  end

  defp to_struct_checked(%name{} = actual, %{} = expected) do
    expected
    |> Stream.map(fn {k, v} -> {k, to_struct_checked(Map.get(actual, k), v)} end)
    |> Map.new()
    |> then(&struct!(name, &1))
  end

  defp to_struct_checked(_actual, expected) do
    expected
  end

  defp parse_type(%SpecTestCase{handler: handler}) do
    Module.concat(SszTypes, handler)
  end
end
