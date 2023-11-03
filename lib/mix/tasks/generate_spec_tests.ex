defmodule Mix.Tasks.GenerateSpecTests do
  @moduledoc """
  Generates ExUnit test cases that will call the runners with the appropriate
  yaml files as input.

  Generated tests are in test/generated/<config>/<fork>/<runner>. Each runner
  has its own folder.
  """

  use Mix.Task
  require Logger

  @runners ["bls", "epoch_processing", "operations", "shuffling", "ssz_static"]
  @configs ["mainnet", "minimal"]
  @forks ["altair", "deneb", "phase0"]

  @shortdoc "Generates tests for spec test files"
  @impl Mix.Task
  def run(_args) do
    for config <- @configs, runner <- @runners do
      generate_test(config, "capella", runner)
    end

    for fork <- @forks, runner <- @runners do
      generate_test("general", fork, runner)
    end

    File.touch(Path.join(["test", "generated"]))
  end

  defp generate_test(config, fork, runner) do
    cases = SpecTestUtils.cases_for(fork: fork, config: config, runner: runner)

    if cases != [] do
      Logger.info("Generating tests for #{config}-#{fork}-#{runner}.")

      # Create the parent dir if not present.
      dirname = Path.join(["test", "generated", config, fork])
      File.mkdir_p!(dirname)
      content = test_module(cases, config, fork, runner)
      File.write!(Path.join(dirname, "#{runner}.exs"), content)
    end
  end

  defp test_module(cases, config, fork, runner) do
    r = Macro.camelize(runner)
    c = Macro.camelize(config)
    f = Macro.camelize(fork)

    module_name = "Elixir.#{c}.#{f}.#{r}Test" |> String.to_atom()
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

    cases_txt = Enum.map_join(cases, fn testcase -> generate_case(runner_module, testcase) end)

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
