defmodule SpecTestUtils do
  use ExUnit.Case

  def get_all_cases do
    ["tests"]
    |> Stream.concat(["*"] |> Stream.cycle() |> Stream.take(6))
    |> Enum.join("/")
    |> Path.wildcard()
    |> Stream.map(&Path.relative_to(&1, "tests"))
    |> Stream.map(&Path.split/1)
  end
end

defmodule SSZTestRunner do
  use ExUnit.Case

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

defmodule SpecTest do
  use ExUnit.Case

  runner_map = %{
    "ssz_static" => SSZTestRunner
  }

  # To filter tests, use:
  #  (only spectests) ->
  #   mix test --only spectest
  #  (only general) ->
  #   mix test --only config:general
  #  (only ssz_generic) ->
  #   mix test --only runner:ssz_generic
  #  (one specific test) ->
  #   mix test --only test:"test c:`config` f:`fork` r:`runner h:`handler` s:suite` -> `case`"
  #
  for [config, fork, runner, handler, suite, cse] <- SpecTestUtils.get_all_cases(),
      # Tests are too many to run all at the same time. We should pin a
      # `config` (and `fork` in the case of `minimal`).
      fork == "capella",
      config == "minimal" do
    test_name = "c:#{config} f:#{fork} r:#{runner} h:#{handler} s:#{suite} -> #{cse}"

    test_runner = Map.get(runner_map, runner)

    @tag :spectest
    @tag config: config
    @tag fork: fork
    @tag runner: runner
    @tag suite: suite
    if test_runner == nil do
      @tag :skip
      test test_name do
        assert false, "unimplemented"
      end
    else
      test_dir = "tests/#{config}/#{fork}/#{runner}/#{handler}/#{suite}/#{cse}"

      test test_name do
        unquote(test_runner).run_test_case(unquote(test_dir))
      end
    end
  end
end
