# General application configuration
import Config

# Configure fork
# Available: "deneb"
# Used only for testing

fork_raw = File.read!(".fork_version") |> String.trim()

fork =
  case fork_raw do
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

# Load minimal config by default, to allow schema checking
config :lambda_ethereum_consensus, ChainSpec,
  config: MinimalConfig,
  genesis_validators_root: <<0::256>>
