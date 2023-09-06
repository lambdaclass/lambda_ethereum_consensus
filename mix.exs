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
      extra_applications: [:logger],
      mod: {LambdaEthereumConsensus.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tesla, "~> 1.4"},
      {:jason, ">= 1.0.0"},
      {:joken, "~> 2.6"},
      {:rustler, "~> 0.29.1"},
      {:broadway, "~> 1.0"},
      {:yaml_elixir, "~> 2.8", only: [:test]},
      {:snappyer, "~> 1.2", only: [:test]},
      {:stream_data, "~> 0.6", only: [:test]},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp dialyzer do
    [
      # https://elixirforum.com/t/help-with-dialyzer-output/15202/5
      plt_add_apps: [:ex_unit],
      plt_file: {:no_warn, "priv/plts/project.plt"}
    ]
  end

  defp compiler_paths(:test), do: ["test/spec"] ++ compiler_paths(:prod)
  defp compiler_paths(_), do: ["lib"]
end
