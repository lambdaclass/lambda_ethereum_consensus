defmodule SpecTestGenerator do
  @moduledoc """
  Generator for running the spec tests.
  """
  @all_cases ["tests"]
             |> Stream.concat(["*"] |> Stream.cycle() |> Stream.take(6))
             |> Enum.join("/")
             |> Path.wildcard()
             |> Stream.map(&Path.relative_to(&1, "tests"))
             |> Stream.map(&Path.split/1)
             |> Enum.map(&SpecTestCase.new/1)

  @runner_map %{
    "ssz_static" => SSZStaticTestRunner,
    "bls" => BLSTestRunner,
    "operations" => OperationsTestRunner
  }

  def all_cases, do: @all_cases
  def runner_map, do: @runner_map

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
  # Tests are too many to run all at the same time. We should pin a
  # `config` (and `fork` in the case of `minimal`).
  defmacro generate_tests(pinned_config, pinned_fork \\ "") do
    quote bind_quoted: [
            pinned_config: pinned_config,
            pinned_fork: pinned_fork
          ] do
      paths = Path.wildcard("tests/#{pinned_config}/#{pinned_fork}/**")
      paths_hash = :erlang.md5(paths)

      for path <- paths do
        @external_resource path
      end

      # Recompile module only if corresponding dir layout changed
      def __mix_recompile__? do
        Path.wildcard(unquote("tests/#{pinned_config}/#{pinned_fork}/**"))
        |> :erlang.md5() != unquote(paths_hash)
      end

      for testcase <- SpecTestGenerator.all_cases(),
          pinned_fork in [testcase.fork, ""],
          testcase.config == pinned_config do
        test_name = SpecTestCase.name(testcase)

        test_runner = Map.get(SpecTestGenerator.runner_map(), testcase.runner)

        @tag :spectest
        @tag config: testcase.config,
             fork: testcase.fork,
             runner: testcase.runner,
             handler: testcase.handler,
             suite: testcase.suite
        if test_runner == nil do
          @tag :skip
          test test_name
        else
          if test_runner.skip?(testcase) do
            @tag :skip
          end

          @tag :implemented_spectest
          test test_name do
            unquote(test_runner).run_test_case(unquote(Macro.escape(testcase)))
          end
        end
      end
    end
  end
end
