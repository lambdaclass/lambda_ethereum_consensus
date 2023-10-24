defmodule TestRunner do
  @moduledoc """
  Behaviour for test runners used by the test generator.
  """

  @doc """
  Adds behaviour and default implementation for `skip?/1` (run all tests).
  """
  defmacro __using__(runner_dir) do
    quote([]) do
      paths = case_files(unquote(runner_dir))
      @paths_hash = :erlang.md5(paths)
      @pinned_fork "capella"

      # Recompile this module if a test yaml is modified.
      for path <- paths do
        @external_resource path
      end

      # Recompile this module if a test yaml is added.
      def __mix_recompile__? do
        (case_files(unquote(runner_dir)) |> :erlang.md5() != @paths_hash) |> IO.inspect(label: "Recompiling #{unquote(runner_dir)}")
      end

      @behaviour TestRunner
      def skip?(_testcase), do: false
      defoverridable skip?: 1

      defp case_files(runner_dir) do
        Path.join([SpecTestUtils.vectors_dir(), "*", @pinned_fork, runner_dir, "**"])
        |> Path.wild_card()
      end
    end
  end

  @doc """
  Returns true if the given testcase should be skipped
  """
  @callback skip?(testcase :: SpecTestCase.t()) :: boolean

  @doc """
  Runs the given test case. This function should only return
  if the test case passes. To ignore test cases use `skip?/1`.
  """
  @callback run_test_case(testcase :: SpecTestCase.t()) :: any
end
