defmodule TestRunner do
  @moduledoc """
  Behaviour for test runners used by the test generator.
  """

  @doc """
  Adds behaviour and default implementation for `skip?/1` (run all tests).
  """
  defmacro __using__(opts \\ []) do
    runner_dir = Keyword.fetch!(opts, :runner)
    skipped_handlers = Keyword.get(opts, :skipped_handlers, [])
    res = quote do
      use ExUnit.Case, async: false

      paths = SpecTestUtils.cases_for(fork: "capella", runner: unquote(runner_dir))
      @paths_hash :erlang.md5(paths)

      # Recompile this module if a test yaml is modified.
      for path <- paths do
        @external_resource path
      end

      # Recompile this module if a test yaml is added.
      def __mix_recompile__? do
        paths = SpecTestUtils.cases_for(fork: "capella", runner: unquote(runner_dir))
        :erlang.md5(paths) != @paths_hash
      end

      @behaviour TestRunner

      IO.inspect("Generating tests for #{inspect(__MODULE__)}")
      cases = paths
      |> Stream.map(&Path.relative_to(&1, SpecTestUtils.vectors_dir()))
      |> Stream.map(&Path.split/1)
      |> Enum.map(&SpecTestCase.new/1)

      for testcase <- cases do
        test_name = SpecTestCase.name(testcase)

        @tag :spectest
        @tag config: testcase.config,
             fork: testcase.fork,
             runner: testcase.runner,
             handler: testcase.handler,
             suite: testcase.suite

        if testcase.handler in unquote(skipped_handlers) do
          @tag :skip
        end
        @tag :implemented_spectest
        test test_name do
          Application.put_env(:lambda_ethereum_consensus, ChainSpec, config: testcase.config)
          run_test_case(testcase)
        end
      end
      IO.inspect("Finished generating tests for #{inspect(__MODULE__)}")
    end
    res
  end

  @doc """
  Runs the given test case. This function should only return
  if the test case passes.
  """
  @callback run_test_case(testcase :: SpecTestCase.t()) :: any
end
