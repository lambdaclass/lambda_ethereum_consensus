defmodule SpecTestGenerator do
  @moduledoc """
  Generator for running the spec tests.
  """

  @vectors_dir SpecTestUtils.vectors_dir()

  def to_cases(case_files) do
    case_files
    |> Stream.map(&Path.relative_to(&1, @vectors_dir))
    |> Stream.map(&Path.split/1)
    |> Enum.map(&SpecTestCase.new/1)
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
  defmacro generate_tests(paths, runner_module) do
    quote do
      for testcase <- paths |> to_cases() do
        test_name = SpecTestCase.name(testcase)

        @tag :spectest
        @tag config: testcase.config,
             fork: testcase.fork,
             runner: testcase.runner,
             handler: testcase.handler,
             suite: testcase.suite
        if test_runner.skip?(testcase) do
          @tag :skip
        end

        @tag :implemented_spectest
        test test_name do
          Application.put_env(:lambda_ethereum_consensus, ChainSpec, config: testcase.config)
          unquote(runner_module).run_test_case(unquote(Macro.escape(testcase)))
        end
      end
    end
  end
end
