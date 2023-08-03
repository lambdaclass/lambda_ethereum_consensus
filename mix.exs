defmodule LambdaEthereumConsensus.MixProject do
  use Mix.Project

  def project do
    [
      app: :lambda_ethereum_consensus,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      { :rustler, "~> 0.29.1" }
    ]
  end
end
