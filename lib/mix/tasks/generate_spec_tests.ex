defmodule Mix.Tasks.GenerateSpecTests do
  use Mix.Task
  require Logger

  @runners ["bls", "epoch_processing", "operations", "shuffling", "ssz_static"]

  @shortdoc "Generates tests for spec test files"
  def run(_args) do
    @runners
    |> Enum.each(&generate_for_runner/1)
  end

  defp generate_for_runner(runner) do
    Logger.info("Generating tests for #{runner}")
    SpecTestUtils.cases_for(fork: "capella", config: "mainnet", runner: runner)
    |> generate_tests(runner)
    |> then(&File.write!("test/generated/#{runner}.exs", &1))
  end

  defp generate_tests(cases, runner) do
    module_name = "Elixir." <> Macro.camelize(runner) <> "Test" |> String.to_atom()
    runner_module = "Elixir." <> Macro.camelize(runner) <> "TestRunner" |> String.to_atom()
    header = """
    defmodule #{module_name} do
      use ExUnit.Case, async: false
    """
    footer = """
    end
    """
    cases_txt = Enum.map(cases, fn testcase -> generate_case(runner_module, testcase) end) |> Enum.join()
    header <> cases_txt <> footer
  end

  defp generate_case(runner_module, testcase) do
    """
      #{if runner_module.skip?(testcase), do: "\n@tag :skip", else: ""}
      test "#{SpecTestCase.name(testcase)}" do
        testcase = #{inspect(testcase)}
        #{runner_module}.run_test_case(testcase)
      end
    """
  end
end
