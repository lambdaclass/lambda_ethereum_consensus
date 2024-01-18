# General application configuration
import Config

# Configure logging
config :logger, level: :info, truncate: :infinity

## TODO: we might want to enable this with a CLI flag
## Uncomment to log to a file
# config :logger, :default_handler,
#   config: [
#     file: ~c"logs/system.log",
#     filesync_repeat_interval: 5000,
#     file_check: 5000,
#     max_no_bytes: 10_000_000,
#     max_no_files: 5,
#     compress_on_rotate: true
#   ]

# Configures the phoenix endpoint
config :lambda_ethereum_consensus, BeaconApi.Endpoint,
  http: [port: 4000],
  url: [host: "localhost"],
  render_errors: [
    formats: [json: BeaconApi.ErrorJSON],
    layout: false
  ]

config :lambda_ethereum_consensus, LambdaEthereumConsensus.Telemetry, enable: true

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
