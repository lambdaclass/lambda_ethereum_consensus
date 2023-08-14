defmodule SpecTestUtils do
  use ExUnit.Case

  def get_test_cases() do
    suites = File.ls!("test-vectors/tests/minimal/phase0/ssz_static/Checkpoint")

    for suite <- suites do
      cases = File.ls!("test-vectors/tests/minimal/phase0/ssz_static/Checkpoint/#{suite}")

      {suite, cases}
    end
  end
end

defmodule SpecTest do
  use ExUnit.Case

  defp run_test_case(case_dir) do
    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, _decompressed} = :snappyer.decompress(compressed)

    _expected = YamlElixir.read_from_file!(case_dir <> "/value.yaml")
    _expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    # assert_ssz(decompressed, expected, expected_root)
  end

  defp assert_ssz(serialized, expected, expected_root) do
    value = SSZ.deserialize(serialized)
    assert value == expected

    root = SSZ.hash_tree_root(value)
    assert root == expected_root
  end

  for {suite, cases} <- SpecTestUtils.get_test_cases() do
    for cse <- cases do
      @tag :skip
      test "#{suite} #{cse}" do
        # unquote is needed to convert vars to literals
        suite = unquote(suite)
        cse = unquote(cse)
        test_dir = "test-vectors/tests/minimal/phase0/ssz_static/Checkpoint/#{suite}/#{cse}"
        run_test_case(test_dir)
      end
    end
  end
end
