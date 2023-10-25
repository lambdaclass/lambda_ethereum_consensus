defmodule Mix.Tasks.GenerateSpecTests do
  use Mix.Task
  require Logger

  @runners ["bls", "epoch_processing", "operations", "shuffling", "ssz_static"]
  @configs ["mainnet", "minimal"]

  @shortdoc "Generates tests for spec test files"
  def run(_args) do
    for config <- @configs,
        runner <- @runners do
          # Create the parent dir if not present.
          dirname = Path.join(["test", "generated", config])
          File.mkdir_p!(dirname)

          cases = SpecTestUtils.cases_for(fork: "capella", config: config, runner: runner)

          if cases != [] do
            Logger.info("Generating tests for #{config}-#{runner}.")
            content = generate_tests(cases, config, runner)
            File.write!(Path.join(dirname, "#{runner}.exs"), content)
          end
    end
  end

  defp generate_tests(cases, config, runner) do
    r = Macro.camelize(runner)
    c = Macro.camelize(config)

    module_name = "Elixir.#{c}.#{r}Test" |> String.to_atom()
    runner_module = "Elixir.#{r}TestRunner" |> String.to_atom()

    header = """
    defmodule #{module_name} do
      use ExUnit.Case, async: false

      setup_all do
        Application.put_env(:lambda_ethereum_consensus, ChainSpec, config: #{chain_spec_config(config)})
      end
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

  defp chain_spec_config("minimal"), do: MinimalConfig
  defp chain_spec_config("mainnet"), do: MainnetConfig
  defp chain_spec_config("general"), do: MainnetConfig
end
