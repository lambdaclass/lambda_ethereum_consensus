defmodule SpecTestUtils do
  use ExUnit.Case

  def get_all_cases() do
    ["test-vectors", "tests"]
    |> Stream.concat(["*"] |> Stream.cycle() |> Stream.take(6))
    |> Enum.join("/")
    |> Path.wildcard()
    |> Stream.map(&Path.relative_to(&1, "test-vectors/tests"))
    |> Stream.map(&Path.split/1)
  end
end

defmodule SSZTestRunner do
  use ExUnit.Case

  def run_test_case(case_dir) do
    compressed = File.read!(case_dir <> "/serialized.ssz_snappy")
    assert {:ok, _decompressed} = :snappyer.decompress(compressed)

    _expected = YamlElixir.read_from_file!(case_dir <> "/value.yaml")
    _expected_root = YamlElixir.read_from_file!(case_dir <> "/roots.yaml")

    # assert_ssz(decompressed, expected, expected_root)
  end

  def assert_ssz(serialized, expected, expected_root) do
    value = SSZ.deserialize(serialized)
    assert value == expected

    root = SSZ.hash_tree_root(value)
    assert root == expected_root
  end
end

defmodule SpecTest do
  use ExUnit.Case

  @runner_map %{
    "ssz_generic" => SSZTestRunner
  }

  for [config, fork, runner, handler, suite, cse] <- SpecTestUtils.get_all_cases() do
    test_name = "c:#{config} f:#{fork} r:#{runner} h:#{handler} s:#{suite} -> #{cse}"

    test_runner = Map.get(@runner_map, runner)

    unless test_runner == nil do
      test_dir = "test-vectors/tests/#{config}/#{fork}/#{runner}/#{handler}/#{suite}/#{cse}"
      @tag :skip
      @tag :spectest
      @tag config: config
      @tag fork: fork
      @tag runner: runner
      @tag suite: suite
      test test_name do
        unquote(test_runner).run_test_case(unquote(test_dir))
      end
    end
  end
end
