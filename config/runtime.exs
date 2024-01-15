import Config

{args, _remaining_args, _errors} =
  OptionParser.parse(System.argv(),
    switches: [
      network: :string,
      checkpoint_sync: :string,
      execution_endpoint: :string,
      execution_jwt: :string,
      mock_execution: :boolean
    ]
  )

network = Keyword.get(args, :network, "mainnet")
checkpoint_sync = Keyword.get(args, :checkpoint_sync)
execution_endpoint = Keyword.get(args, :execution_endpoint, "http://localhost:8551")
jwt_path = Keyword.get(args, :execution_jwt)
mock_execution = Keyword.get(args, :mock_execution, false)

config :lambda_ethereum_consensus, LambdaEthereumConsensus.ForkChoice,
  checkpoint_sync: checkpoint_sync

configs_per_network = %{
  "minimal" => MinimalConfig,
  "mainnet" => MainnetConfig,
  "sepolia" => SepoliaConfig
}

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
    do: LambdaEthereumConsensus.Execution.EngineApi.Debug,
    else: LambdaEthereumConsensus.Execution.EngineApi.Tesla

config :lambda_ethereum_consensus, LambdaEthereumConsensus.Execution.EngineApi,
  endpoint: execution_endpoint,
  jwt_secret: jwt_secret,
  implementation: implementation,
  version: "2.0"
