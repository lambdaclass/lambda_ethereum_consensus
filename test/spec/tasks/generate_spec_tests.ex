defmodule Mix.Tasks.GenerateSpecTests do
  @moduledoc """
  Generates ExUnit test cases that will call the runners with the appropriate
  yaml files as input.

  Generated tests are in test/generated/<config>/<fork>/<runner>. Each runner
  has its own folder.
  """

  use Mix.Task
  require Logger

  @configs ["mainnet", "minimal", "general"]
  @forks ["phase0", "altair", "bellatrix", "capella", "deneb"]
  @current_fork Application.compile_env!(:lambda_ethereum_consensus, :fork) |> Atom.to_string()

  @shortdoc "Generates tests for spec test files"
  @impl Mix.Task
  def run(_args) do
    generated_folder = Path.join(["test", "generated"])
    {:ok, file_names} = Path.join(["test", "spec", "runners"]) |> File.ls()
    runners = Enum.map(file_names, &Path.basename(&1, ".ex"))

    # Empty test folder
    File.rm_rf!(generated_folder)
    File.mkdir_p!(generated_folder)

    # Generate all tests for current fork
    for config <- @configs, runner <- runners do
      generate_test(config, @current_fork, runner)
    end

    # Generate tests for all forks in general preset
    for fork <- @forks, runner <- runners do
      generate_test("general", fork, runner)
    end

    # Generate shuffling tests for all testcases
    for config <- @configs, fork <- @forks do
      generate_test(config, fork, "shuffling")
    end

    File.touch(generated_folder)
  end

  defp generate_test(config, fork, runner) do
    cases = SpecTestUtils.cases_for(fork: fork, config: config, runner: runner)

    if cases != [] do
      Logger.info("Generating tests for #{config}-#{fork}-#{runner}")

      # Create the parent dir if not present.
      dirname = Path.join(["test", "generated", config, fork])
      File.mkdir_p!(dirname)
      content = test_module(cases, config, fork, runner)
      File.write!(Path.join(dirname, "#{runner}.exs"), content)
    end
  end

  defp test_module(cases, config, fork, runner) do
    c = Macro.camelize(config)
    f = Macro.camelize(fork)
    r = Macro.camelize(runner)

    module_name = "Elixir.#{c}.#{f}.#{r}Test" |> String.to_atom()
    runner_module = "Elixir.#{r}TestRunner" |> String.to_atom()

    # TODO: we can isolate tests that use the DB from each other by using ExUnit's tmp_dir context option.
    header = """
    defmodule #{module_name} do
      use ExUnit.Case, async: false

      setup_all do
        start_link_supervised!({LambdaEthereumConsensus.Store.Db, dir: "tmp/#{config}_#{fork}_#{runner}_test_db"})
        start_link_supervised!(LambdaEthereumConsensus.Store.Blocks)
        start_link_supervised!(LambdaEthereumConsensus.Store.BlockStates)
        Application.fetch_env!(:lambda_ethereum_consensus, ChainSpec)
        |> Keyword.put(:config, #{chain_spec_config(config)})
        |> then(&Application.put_env(:lambda_ethereum_consensus, ChainSpec, &1))
      end

      setup do
        on_exit(fn -> LambdaEthereumConsensus.StateTransition.Cache.clear_cache() end)
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
