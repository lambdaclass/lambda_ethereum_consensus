defmodule SSZStaticTestRunner do
  use ExUnit.CaseTemplate

  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """

  @type_equivalence %{
    "PendingAttestation" => "PendingAttestation"
  }

  @enabled [
    "AttestationData",
    "Checkpoint",
    "Eth1Data",
    "Fork",
    "ForkData",
    "PendingAttestation",
    "Validator"
  ]

  @doc """
  Returns true if the given testcase should be skipped
  """
  def skip?(testcase) do
    not Enum.member?(@enabled, testcase.handler)
  end

  @doc """
  Runs the given test case.
  """
  def run_test_case(%SpecTestCase{} = testcase) do
    case_dir = SpecTestCase.dir(testcase)

    schema = handler_name_to_type(testcase.handler)

    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    expected =
      YamlElixir.read_from_file!(case_dir <> "/value.yaml")
      |> parse_yaml()

    expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    assert_ssz(schema, decompressed, expected, expected_root)
  end

  defp parse_yaml(map) when is_map(map) do
    map
    |> Stream.map(&parse_yaml/1)
    |> Map.new()
  end

  defp parse_yaml({k, "0x" <> hash}) do
    v =
      hash
      |> Base.decode16!([{:case, :lower}])

    {String.to_existing_atom(k), v}
  end

  defp parse_yaml({k, map}) when is_map(map) do
    v = parse_yaml(map)
    {String.to_existing_atom(k), v}
  end

  defp parse_yaml({k, v}), do: {String.to_existing_atom(k), v}

  defp assert_ssz(schema, real_serialized, real_deserialized, _expected_root) do
    # assert root is expected when we implement SSZ hashing

    {:ok, deserialized} = Ssz.from_ssz(real_serialized, schema)
    real_deserialized = to_struct_checked(deserialized, real_deserialized)

    assert deserialized == real_deserialized

    {:ok, serialized} = Ssz.to_ssz(real_deserialized)
    assert serialized == real_serialized
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

  defp handler_name_to_type(handler) do
    Map.get(@type_equivalence, handler, handler)
    |> then(&Module.concat(SszTypes, &1))
  end
end
