import Config

config :lambda_ethereum_consensus,
  jwt_secret: "0000000000000000000000000000000000000000000000000000000000000000"

config :tesla, :adapter, Tesla.Adapter.Hackney
