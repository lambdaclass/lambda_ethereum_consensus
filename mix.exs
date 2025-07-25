defmodule LambdaEthereumConsensus.MixProject do
  use Mix.Project

  def project() do
    [
      app: :lambda_ethereum_consensus,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      elixirc_paths: compiler_paths(Mix.env()),
      warn_test_pattern: "_remove_warning.exs",
      preferred_cli_env: [
        dialyzer: :test,
        generate_spec_tests: :test,
        check_enabled_tests: :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application() do
    [
      extra_applications:
        extra_applications(System.get_env("EXTRA_APPLICATIONS")) ++
          [:logger, :runtime_tools, :observer],
      mod: {LambdaEthereumConsensus.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps() do
    [
      {:phoenix, "~> 1.7.7"},
      {:plug_cowboy, "~> 2.5"},
      {:tesla, "~> 1.4"},
      {:exleveldb, "~> 0.14"},
      {:eleveldb,
       git: "https://github.com/basho/eleveldb", ref: "riak_kv-3.0.12", override: true},
      {:jason, "~> 1.4"},
      {:scrypt_elixir, "~> 0.1.1", hex: :scrypt_elixir_copy},
      {:joken, "~> 2.6"},
      {:rustler, "~> 0.32", runtime: false},
      {:snappyer, "~> 1.2"},
      {:yaml_elixir, "~> 2.8"},
      {:timex, "~> 3.7"},
      {:recase, "~> 0.7"},
      {:rexbug, "~> 1.0"},
      {:eep, git: "https://github.com/virtan/eep", branch: "master"},
      {:protobuf, "~> 0.14.0"},
      {:aja, "~> 0.6"},
      {:logfmt_ex, "~> 0.4.2"},
      {:ex2ms, "~> 1.6", runtime: false},
      {:eflambe, "~> 0.3.1"},
      {:patch, "~> 0.16.0", only: [:test]},
      {:stream_data, "~> 1.0", only: [:test]},
      {:benchee, "~> 1.2", only: [:dev]},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:open_api_spex, "~> 3.18"},
      {:crc32c, git: "https://github.com/lambdaclass/crc32c", branch: "bump-rustler-32"},
      {:recode, "~> 0.7", only: [:dev, :test]},
      {:sentry, "~> 10.9.0"},
      {:prom_ex, "~> 1.11.0"},
      {:flama, git: "https://github.com/lambdaclass/ht1223_tracer"},
      {:uuid, "~> 1.1"},
      # TODO: (#1368) We might want to use phoenix_pubsub instead and do our implementation of SSE.
      {:sse, "~> 0.4"},
      {:event_bus, ">= 1.6.0"}
    ]
  end

  defp dialyzer() do
    [
      # https://elixirforum.com/t/help-with-dialyzer-output/15202/5
      plt_add_apps: [:ex_unit, :mix],
      plt_file: {:no_warn, "priv/plts/project.plt"}
    ]
  end

  defp extra_applications("WX"), do: [:wx]
  defp extra_applications(_), do: []

  defp compiler_paths(:test),
    do: ["test/spec", "test/fixtures"] ++ compiler_paths(:prod)

  defp compiler_paths(_), do: ["lib", "proto"]
end
