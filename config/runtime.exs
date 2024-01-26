import Config

{args, remaining_args} =
  OptionParser.parse!(System.argv(),
    strict: [
      network: :string,
      checkpoint_sync: :string,
      execution_endpoint: :string,
      execution_jwt: :string,
      mock_execution: :boolean,
      db_only: :boolean
    ]
  )

if not Enum.empty?(remaining_args) do
  IO.puts("Unexpected argument received: #{Enum.take(remaining_args, 1)}")
  System.halt(1)
end

network = Keyword.get(args, :network, "mainnet")
checkpoint_sync = Keyword.get(args, :checkpoint_sync)
execution_endpoint = Keyword.get(args, :execution_endpoint, "http://localhost:8551")
jwt_path = Keyword.get(args, :execution_jwt)

config :lambda_ethereum_consensus, LambdaEthereumConsensus.ForkChoice,
  checkpoint_sync: checkpoint_sync

configs_per_network = %{
  "minimal" => MinimalConfig,
  "mainnet" => MainnetConfig,
  "sepolia" => SepoliaConfig
}

mode =
  if Keyword.get(args, :db_only, false) do
    :db_only
  else
    :full
  end

config :lambda_ethereum_consensus, LambdaEthereumConsensus, mode: mode

mock_execution = Keyword.get(args, :mock_execution, mode == :db_only or is_nil(jwt_path))

config :lambda_ethereum_consensus, ChainSpec, config: configs_per_network |> Map.fetch!(network)

bootnodes = YamlElixir.read_from_file!("config/networks/#{network}/bootnodes.yaml")

# Configures peer discovery
config :lambda_ethereum_consensus, :discovery, port: 9000, bootnodes: bootnodes

jwt_secret =
  if jwt_path do
    File.read!(jwt_path)
  else
    nil
  end

implementation =
  if mock_execution,
    do: LambdaEthereumConsensus.Execution.EngineApi.Mocked,
    else: LambdaEthereumConsensus.Execution.EngineApi.Api

config :lambda_ethereum_consensus, LambdaEthereumConsensus.Execution.EngineApi,
  endpoint: execution_endpoint,
  jwt_secret: jwt_secret,
  implementation: implementation,
  version: "2.0"

# Configures metrics
# TODO: we should set this dynamically
block_time_ms =
  case network do
    "mainnet" -> 12_000
    "sepolia" -> 100
  end

config :lambda_ethereum_consensus, LambdaEthereumConsensus.Telemetry,
  block_processing_buckets: [0.5, 1.0, 1.5, 2, 4, 6, 8] |> Enum.map(&(&1 * block_time_ms))
