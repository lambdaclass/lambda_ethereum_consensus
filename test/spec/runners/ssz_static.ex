defmodule SSZStaticTestRunner do
  use ExUnit.CaseTemplate
  alias LambdaEthereumConsensus.Ssz

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
  def run_test_case(testcase = %SpecTestCase{}) do
    case_dir = SpecTestCase.dir(testcase)

    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    expected =
      YamlElixir.read_from_file!(case_dir <> "/value.yaml")
      |> Stream.map(&parse_yaml/1)
      |> Map.new()

    expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    assert_ssz(testcase, decompressed, expected, expected_root)
  end

  defp parse_yaml({k, "0x" <> hash}) do
    v =
      hash
      |> Base.decode16!([{:case, :lower}])

    {String.to_atom(k), v}
  end

  defp parse_yaml({k, v}), do: {String.to_atom(k), v}

  defp assert_ssz(testcase, serialized, expected, _expected_root) do
    # TODO: assert root is expected when we implement SSZ hashing
    schema =
      "Elixir.#{testcase.handler}"
      |> String.to_atom()

    {:ok, deserialized} = Ssz.from_ssz(schema, serialized)
    assert deserialized == expected
  end
end
