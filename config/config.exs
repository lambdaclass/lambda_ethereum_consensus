# General application configuration
import Config

# Configure fork
# Available: "capella", "deneb"
# Used only for testing
fork_raw = System.get_env("FORK", "capella")

fork =
  case fork_raw do
    "capella" -> :capella
    "deneb" -> :deneb
    v -> raise "Invalid fork specified: #{v}"
  end

IO.puts("compilation done for fork: #{fork_raw}")

config :lambda_ethereum_consensus, :fork, fork

# Configure logging
config :logger, level: :info, truncate: :infinity

config :lambda_ethereum_consensus, LambdaEthereumConsensus.Telemetry, enable: true

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configures the phoenix endpoint
config :lambda_ethereum_consensus, BeaconApi.Endpoint,
  http: [port: 4000],
  url: [host: "localhost"],
  render_errors: [
    formats: [json: BeaconApi.ErrorJSON],
    layout: false
  ]
