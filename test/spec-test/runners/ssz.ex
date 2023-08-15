defmodule SSZTestRunner do
  use ExUnit.CaseTemplate

  def run_test_case(case_dir) do
    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    expected = YamlElixir.read_from_file!(case_dir <> "/value.yaml")
    expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    assert_ssz(decompressed, expected, expected_root)
  end

  def assert_ssz(_serialized, _expected, _expected_root) do
    # add SSZ comparison here
    assert true
  end
end
