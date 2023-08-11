defmodule SpecTest do
  use ExUnit.Case

  defp assert_ssz(serialized, expected, expected_root) do
    value = SSZ.deserialize(serialized)
    assert value == expected

    root = SSZ.hash_tree_root(value)
    assert root == expected_root
  end

  @tag :skip
  test "dummy" do
    case_dir = "test-vectors/tests/minimal/phase0/ssz_static/Checkpoint/ssz_lengthy/case_0"

    assert {:ok, compressed} = File.read(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, decompressed} = :snappyer.decompress(compressed)

    assert {:ok, expected} = YamlElixir.read_from_file(case_dir <> "/value.yaml")
    assert {:ok, expected_root} = YamlElixir.read_from_file(case_dir <> "/roots.yaml")

    assert_ssz(decompressed, expected, expected_root)
  end
end
