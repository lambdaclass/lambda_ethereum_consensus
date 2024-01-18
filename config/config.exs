# General application configuration
import Config

# Configure logging
config :logger, level: :info, truncate: :infinity, utc_log: true

# # Uncomment to log to a file
# # TODO: we might want to enable this with a CLI flag
# config :logger, :default_handler,
#   config: [
#     file: ~c"logs/system.log",
#     filesync_repeat_interval: 5000,
#     file_check: 5000,
#     max_no_bytes: 10_000_000,
#     max_no_files: 5,
#     compress_on_rotate: true
#   ]

# # NOTE: We want to log UTC timestamps, for convenience
# config :logger, utc_log: true

# config :logger, :default_formatter,
#   format: {LogfmtEx, :format},
#   colors: [enabled: false],
#   metadata: [:mfa]

# config :logfmt_ex, :opts,
#   message_key: "msg",
#   timestamp_key: "ts",
#   timestamp_format: :iso8601

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
