# General application configuration
import Config

config :lambda_ethereum_consensus,
  jwt_secret: "0000000000000000000000000000000000000000000000000000000000000000"

# Configures the phoenix endpoint
config :lambda_ethereum_consensus, BeaconApi.Endpoint,
  http: [port: 4000],
  url: [host: "localhost"],
  render_errors: [
    formats: [json: BeaconApi.ErrorJSON],
    layout: false
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
