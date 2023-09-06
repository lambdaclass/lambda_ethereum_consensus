defmodule SSZStaticTestRunner do
  use ExUnit.CaseTemplate

  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """

  @enabled [
    "AttestationData",
    "Checkpoint",
    "Eth1Data",
    "Fork",
    "ForkData",
    "HistoricalBatch",
    "IndexedAttestation",
    "PendingAttestation",
    "Validator",
    "VoluntaryExit",
    "DepositData",
    "Deposit",
    "DepositMessage",
    "HistoricalSummary",
    "Attestation",
    "BeaconBlockHeader",
    "SignedVoluntaryExit",
    "SigningData",
    "SignedBeaconBlockHeader",
    "AttestorSlashing",
    "BLSToExecutionChange",
    "SignedBLSToExecutionChange",
    "ProposerSlashing",
    "SyncAggregate",
    "ExecutionPayload",
    "ExecutionPayloadHeader",
    "Withdrawal",
    "SyncCommittee"
  ]

  @doc """
  Returns true if the given testcase should be skipped
  """
  def skip?(%SpecTestCase{fork: fork, handler: handler}) do
    not Enum.member?(@enabled, handler) or
      (handler in ["ExecutionPayloadHeader", "ExecutionPayload"] and fork != "capella")
  end

  def get_config("minimal"), do: MinimalConfig
  def get_config("mainnet"), do: MainnetConfig
  def get_config(_), do: raise("Unknown config")

  @doc """
  Runs the given test case.
  """
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    schema = parse_type(testcase)

    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    expected =
      YamlElixir.read_from_file!(case_dir <> "/value.yaml")
      |> SpecTestUtils.parse_yaml()

    expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    assert_ssz(schema, decompressed, expected, expected_root)
  end

  defp assert_ssz(schema, real_serialized, real_deserialized, _expected_root) do
    # assert root is expected when we implement SSZ hashing

    {:ok, deserialized} = Ssz.from_ssz(real_serialized, schema)
    real_deserialized = to_struct_checked(deserialized, real_deserialized)

    assert deserialized == real_deserialized

    {:ok, serialized} = Ssz.to_ssz(real_deserialized)
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

  defp parse_type(%SpecTestCase{config: config, handler: handler}) do
    config = get_config(config)

    Map.get(config.get_handler_mapping(), handler, handler)
    |> then(&Module.concat(SszTypes, &1))
  end
end
