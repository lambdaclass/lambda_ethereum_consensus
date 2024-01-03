defmodule LambdaEthereumConsensus.MixProject do
  use Mix.Project

  def project do
    [
      app: :lambda_ethereum_consensus,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      elixirc_paths: compiler_paths(Mix.env()),
      warn_test_pattern: "_remove_warning.exs",
      preferred_cli_env: [
        dialyzer: :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :observer],
      mod: {LambdaEthereumConsensus.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.7.7"},
      {:plug_cowboy, "~> 2.5"},
      {:tesla, "~> 1.4"},
      {:exleveldb, "~> 0.14"},
      {:jason, ">= 1.0.0"},
      {:joken, "~> 2.6"},
      {:rustler, "~> 0.29.1"},
      {:broadway, "~> 1.0"},
      {:snappyer, "~> 1.2"},
      {:yaml_elixir, "~> 2.8"},
      {:timex, "~> 3.7"},
      {:rexbug, "~> 1.0"},
      {:eep, git: "https://github.com/virtan/eep", branch: "master"},
      {:protobuf, "~> 0.12.0"},
      {:uuid, "~> 1.1"},
      {:telemetry, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_metrics_prometheus, "~> 1.1.0"},
      {:eflambe, "~> 0.3.1"},
      {:patch, "~> 0.12.0", only: [:test]},
      {:stream_data, "~> 0.5", only: [:test]},
      {:benchee, "~> 1.2", only: [:dev]},
      {:aja, "~> 0.6"},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      # https://elixirforum.com/t/help-with-dialyzer-output/15202/5
      plt_add_apps: [:ex_unit, :mix],
      plt_file: {:no_warn, "priv/plts/project.plt"}
    ]
  end

  defp compiler_paths(:test), do: ["test/spec", "test/fixtures"] ++ compiler_paths(:prod)
  defp compiler_paths(_), do: ["lib", "proto"]
end
