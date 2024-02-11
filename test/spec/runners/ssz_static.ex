defmodule SszStaticTestRunner do
  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """
  alias LambdaEthereumConsensus.SszEx
  alias LambdaEthereumConsensus.Utils.BitList
  alias LambdaEthereumConsensus.Utils.BitVector
  alias LambdaEthereumConsensus.Utils.Diff

  use ExUnit.CaseTemplate
  use TestRunner

  @disabled [
    # "DepositData",
    "DepositMessage",
    "Eth1Block",
    "Eth1Data",
    "ExecutionPayload",
    "ExecutionPayloadHeader",
    "Fork",
    "ForkData",
    "HistoricalBatch",
    "IndexedAttestation",
    "LightClientBootstrap",
    "LightClientOptimisticUpdate",
    "LightClientUpdate",
    "PowBlock",
    "ProposerSlashing",
    "SignedBeaconBlock",
    "SignedBeaconBlockHeader",
    "SignedContributionAndProof",
    "SignedVoluntaryExit",
    "SignedData",
    "SyncAggregate",
    "SyncAggregatorSelectionData",
    "SyncCommitte",
    "SyncCommitteeContribution",
    "Validator",
    "VoluntaryExit",
    "AggregateAndProof",
    "Attestation",
    "AttestationData",
    "BLSToExecutionChange",
    "BeaconBlock",
    "BeaconBlockBody",
    "BeaconBlockHeader",
    "BeaconState",
    "Checkpoint",
    "Deposit",
    "SignedAggregateAndProof",
    "SignedBLSToExecutionChange",
    "SigningData",
    "SyncCommittee",
    "Withdrawal",
    "AttesterSlashing",
    "HistoricalSummary",
    "PendingAttestation",
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
      |> sanitize(schema)

    %{"root" => expected_root} = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")
    expected_root = expected_root |> SpecTestUtils.sanitize_yaml()

    assert_ssz(schema, decompressed, expected, expected_root)
  end

  defp assert_ssz(schema, real_serialized, real_deserialized, _expected_root) do
    {:ok, deserialized} = SszEx.decode(real_serialized, schema)
    assert Diff.diff(deserialized, real_deserialized) == :unchanged
    {:ok, serialized} = SszEx.encode(real_deserialized, schema)
    assert serialized == real_serialized

    ## TODO Enable when merklelization is enable
    # root = SszEx.hash_tree_root!(real_deserialized)
    # assert root == expected_root
  end

  defp parse_type(%SpecTestCase{handler: handler}) do
    Module.concat(Types, handler)
  end

  def sanitize(container, module) when is_map(container) do
    schema = module.schema() |> Map.new()

    container
    |> Enum.map(fn {k, v} -> {k, sanitize(v, Map.fetch!(schema, k))} end)
    |> then(&struct!(module, &1))
  end

  def sanitize(vector_elements, {:vector, :bool, _size} = _schema), do: vector_elements

  def sanitize(vector_elements, {:vector, module, _size} = _schema) when is_atom(module),
    do:
      vector_elements
      |> Enum.map(&struct!(module, &1))

  def sanitize(bitlist, {:bitlist, _size} = _schema), do: elem(BitList.new(bitlist), 0)
  def sanitize(bitvector, {:bitvector, size} = _schema), do: BitVector.new(bitvector, size)

  def sanitize(bytelist, {:list, {:int, 8}, _size} = _schema)
      when is_integer(bytelist) and bytelist > 0,
      do: :binary.encode_unsigned(bytelist) |> :binary.bin_to_list()

  def sanitize(bytelist, {:list, {:int, 8}, _size} = _schema)
      when is_integer(bytelist) and bytelist == 0,
      do: []

  def sanitize(bytelist, {:list, {:int, 8}, _size} = _schema),
    do: :binary.bin_to_list(bytelist)

  def sanitize(other, _schema), do: other
end
