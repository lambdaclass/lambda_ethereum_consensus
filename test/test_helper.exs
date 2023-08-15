ExUnit.start()

defmodule SpecTestCase do
  @enforce_keys [:config, :fork, :runner, :handler, :suite, :case]
  defstruct [:config, :fork, :runner, :handler, :suite, :case]

  def new([config, fork, runner, handler, suite, cse]) do
    %SpecTestCase{
      config: config,
      fork: fork,
      runner: runner,
      handler: handler,
      suite: suite,
      case: cse
    }
  end

  def name(%SpecTestCase{
        config: config,
        fork: fork,
        runner: runner,
        handler: handler,
        suite: suite,
        case: cse
      }) do
    "c:#{config} f:#{fork} r:#{runner} h:#{handler} s:#{suite} -> #{cse}"
  end

  def dir(%SpecTestCase{
        config: config,
        fork: fork,
        runner: runner,
        handler: handler,
        suite: suite,
        case: cse
      }) do
    "tests/#{config}/#{fork}/#{runner}/#{handler}/#{suite}/#{cse}"
  end
end

defmodule SpecTestUtils do
  @all_cases ["tests"]
             |> Stream.concat(["*"] |> Stream.cycle() |> Stream.take(6))
             |> Enum.join("/")
             |> Path.wildcard()
             |> Stream.map(&Path.relative_to(&1, "tests"))
             |> Stream.map(&Path.split/1)
             |> Enum.map(&SpecTestCase.new/1)

  @runner_map %{
    "ssz_static" => SSZTestRunner
  }

  def all_cases, do: @all_cases
  def runner_map, do: @runner_map

  defmacro __using__(_) do
    Path.wildcard("test/spec/runners/*.ex")
    |> Enum.each(&Code.require_file/1)
  end

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
      for testcase <- SpecTestUtils.all_cases(),
          pinned_fork in [testcase.fork, ""],
          testcase.config == pinned_config do
        test_name = SpecTestCase.name(testcase)

        test_runner = Map.get(SpecTestUtils.runner_map(), testcase.runner)

        @tag :spectest
        @tag config: testcase.config, fork: testcase.fork
        @tag runner: testcase.runner, suite: testcase.suite
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
