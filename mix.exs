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
      elixirc_path: compiler_paths(Mix.env()),
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
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:yaml_elixir, "~> 2.8", only: [:test]},
      {:snappyer, "~> 1.2", only: [:test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 0.6", only: :test},
      {:rustler, "~> 0.29.1"}
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/project.plt"}
    ]
  end

  defp compiler_paths(:test), do: ["test/spec-test/runners"] ++ compiler_paths(:prod)
  defp compiler_paths(_), do: ["lib"]
end
