# General application configuration
import Config

# Configure logging
config :logger, level: :info, truncate: :infinity

config :lambda_ethereum_consensus, ChainSpec, config: MainnetConfig

config :lambda_ethereum_consensus, LambdaEthereumConsensus.Execution.EngineApi,
  endpoint: "http://localhost:8551",
  version: "2.0",
  # Will be set by CLI
  jwt_secret: nil

# Configures the phoenix endpoint
config :lambda_ethereum_consensus, BeaconApi.Endpoint,
  http: [port: 4000],
  url: [host: "localhost"],
  render_errors: [
    formats: [json: BeaconApi.ErrorJSON],
    layout: false
  ]

# Configures peer discovery
config :lambda_ethereum_consensus, :discovery, port: 9000

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
