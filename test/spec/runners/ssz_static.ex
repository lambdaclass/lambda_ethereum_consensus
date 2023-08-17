defmodule SSZStaticTestRunner do
  use ExUnit.CaseTemplate

  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """

  @doc """
  Returns true if the given testcase should be skipped
  """
  def skip?(testcase) do
    # add SSZ test case skipping here
    testcase.handler not in ["Checkpoint", "Fork", "ForkData"]
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
      schema
      |> struct(
        YamlElixir.read_from_file!(case_dir <> "/value.yaml")
        |> Stream.map(&parse_yaml/1)
        |> Map.new()
      )

    expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    assert_ssz(schema, decompressed, expected, expected_root)
  end

  defp parse_yaml({k, "0x" <> hash}) do
    v =
      hash
      |> Base.decode16!([{:case, :lower}])

    {String.to_atom(k), v}
  end

  defp parse_yaml({k, v}), do: {String.to_atom(k), v}

  defp assert_ssz(schema, serialized, expected, _expected_root) do
    # assert root is expected when we implement SSZ hashing

    {:ok, deserialized} = Ssz.from_ssz(serialized, schema)
    assert deserialized == expected
  end

  defp handler_name_to_type(handler) do
    prefix = to_string(SszTypes)

    (prefix <> "." <> handler)
    |> String.to_atom()
  end
end
