defmodule TestRunner do
  @moduledoc """
  Behaviour for test runners used by the test generator.
  """

  @doc """
  Adds behaviour and default implementation for `skip?/1` (run all tests).
  """
  defmacro __using__(_) do
    quote([]) do
      @behaviour TestRunner
      def skip?(_testcase), do: false
      defoverridable skip?: 1
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
