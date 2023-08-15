defmodule SSZTestRunner do
  use ExUnit.CaseTemplate

  @moduledoc """
  Runner for SSZ test cases. `run_test_case/1` is the main entrypoint.
  """

  @doc """
  Returns true if the given testcase should be skipped
  """
  def skip?(_testcase) do
    # add SSZ test case skipping here
    false
  end

  @doc """
  Runs the given test case.
  """
  def run_test_case(testcase = %SpecTestCase{}) do
    case_dir = SpecTestCase.dir(testcase)

    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    expected = YamlElixir.read_from_file!(case_dir <> "/value.yaml")
    expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    assert_ssz(decompressed, expected, expected_root)
  end

  defp assert_ssz(_serialized, _expected, _expected_root) do
    # add SSZ comparison here
    assert true
  end
end
