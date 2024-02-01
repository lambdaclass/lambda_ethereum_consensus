ExUnit.start()
Application.ensure_all_started([:telemetry, :logger])
# NOTE: logger doesn't fetch configuration from `config/config.exs` in tests
Logger.configure(level: :warning)
# LambdaEthereumConsensus.StateTransition.Cache.initialize_cache()

# Load all modules as ExUnit tests (needed because we use .ex files)
# Copied from https://github.com/elixir-lang/elixir/issues/10983#issuecomment-1133554155
for module <- Application.spec(Mix.Project.config()[:app], :modules) do
  ex_unit = Keyword.get(module.module_info(:attributes), :ex_unit_async, [])

  cond do
    true in ex_unit -> ExUnit.Server.add_async_module(module)
    false in ex_unit -> ExUnit.Server.add_sync_module(module)
    true -> :ok
  end
end
