ExUnit.start()

defmodule SpecTestUtils do
  @all_cases ["tests"]
             |> Stream.concat(["*"] |> Stream.cycle() |> Stream.take(6))
             |> Enum.join("/")
             |> Path.wildcard()
             |> Stream.map(&Path.relative_to(&1, "tests"))
             |> Enum.map(&Path.split/1)

  @runner_map %{
    "ssz_static" => SSZTestRunner
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
      for [config, fork, runner, handler, suite, cse] <- SpecTestUtils.all_cases(),
          pinned_fork in [fork, ""],
          config == pinned_config do
        test_name = "c:#{config} f:#{fork} r:#{runner} h:#{handler} s:#{suite} -> #{cse}"

        test_runner = Map.get(SpecTestUtils.runner_map(), runner)

        @tag :spectest
        @tag config: config
        @tag fork: fork
        @tag runner: runner
        @tag suite: suite
        if test_runner == nil do
          @tag :skip
          test test_name
        else
          test_dir = "tests/#{config}/#{fork}/#{runner}/#{handler}/#{suite}/#{cse}"

          test test_name do
            unquote(test_runner).run_test_case(unquote(test_dir))
          end
        end
      end
    end
  end
end
