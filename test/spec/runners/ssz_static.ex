defmodule SSZStaticTestRunner do
  use ExUnit.CaseTemplate

  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """

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

  @doc """
  Returns true if the given testcase should be skipped
  """
  def skip?(%SpecTestCase{handler: handler}) do
    Enum.member?(@disabled, handler)
  end

  def get_config("minimal"), do: MinimalConfig
  def get_config("mainnet"), do: MainnetConfig
  def get_config(_), do: raise("Unknown config")

  @doc """
  Runs the given test case.
  """
  def run_test_case(%SpecTestCase{config: config} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    schema = parse_type(testcase)
    config = get_config(config)

    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    expected =
      YamlElixir.read_from_file!(case_dir <> "/value.yaml")
      |> SpecTestUtils.parse_yaml()

    expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    assert_ssz(schema, config, decompressed, expected, expected_root)
  end

  defp assert_ssz(schema, config, real_serialized, real_deserialized, _expected_root) do
    # assert root is expected when we implement SSZ hashing

    {:ok, deserialized} = Ssz.from_ssz(real_serialized, schema, config)
    real_deserialized = to_struct_checked(deserialized, real_deserialized)

    assert deserialized == real_deserialized

    {:ok, serialized} = Ssz.to_ssz(real_deserialized, config)
    assert serialized == real_serialized
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
