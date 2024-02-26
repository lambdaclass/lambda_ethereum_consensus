import Config

switches = [
  network: :string,
  checkpoint_sync_url: :string,
  execution_endpoint: :string,
  execution_jwt: :string,
  mock_execution: :boolean,
  mode: :string,
  log_file: :string
]

is_testing = Config.config_env() == :test

# NOTE: we ignore invalid options because `mix test` passes us all test flags
option = if is_testing, do: :switches, else: :strict

{args, remaining_args} = OptionParser.parse!(System.argv(), [{option, switches}])

if not is_testing and not Enum.empty?(remaining_args) do
  invalid_arg = Enum.take(remaining_args, 1)
  IO.puts("Unexpected argument received: #{invalid_arg}")
  System.halt(1)
end

network = Keyword.get(args, :network, "mainnet")
checkpoint_sync_url = Keyword.get(args, :checkpoint_sync_url)
execution_endpoint = Keyword.get(args, :execution_endpoint, "http://localhost:8551")
jwt_path = Keyword.get(args, :execution_jwt)

config :lambda_ethereum_consensus, LambdaEthereumConsensus.ForkChoice,
  checkpoint_sync_url: checkpoint_sync_url

configs_per_network = %{
  "gnosis" => GnosisConfig,
  "minimal" => MinimalConfig,
  "mainnet" => MainnetConfig,
  "sepolia" => SepoliaConfig
}

genesis_validators_root_per_network = %{
  "minimal" => <<0::256>>,
  "mainnet" => Base.decode16!("4B363DB94E286120D76EB905340FDD4E54BFE9F06BF33FF6CF5AD27F511BFE95"),
  "sepolia" => Base.decode16!("D8EA171F3C94AEA21EBC42A1ED61052ACF3F9209C00E4EFBAADDAC09ED9B8078")
}

valid_modes = ["full", "db"]
raw_mode = Keyword.get(args, :mode, "full")

mode =
  if raw_mode in valid_modes do
    String.to_atom(raw_mode)
  else
    IO.puts("Invalid mode given. Valid modes are: #{Enum.join(valid_modes, ", ")}")
    System.halt(2)
  end

config :lambda_ethereum_consensus, LambdaEthereumConsensus, mode: mode
config :lambda_ethereum_consensus, LambdaEthereumConsensus.Store.Db, dir: "level_db/#{network}"

mock_execution = Keyword.get(args, :mock_execution, mode == :db or is_nil(jwt_path))

config :lambda_ethereum_consensus, ChainSpec,
  config: configs_per_network |> Map.fetch!(network),
  genesis_validators_root: genesis_validators_root_per_network |> Map.fetch!(network)

bootnodes = YamlElixir.read_from_file!("config/networks/#{network}/boot_enr.yaml")

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
    "gnosis" -> 6000
    "mainnet" -> 12_000
    "sepolia" -> 100
  end

config :lambda_ethereum_consensus, LambdaEthereumConsensus.Telemetry,
  block_processing_buckets: [0.5, 1.0, 1.5, 2, 4, 6, 8] |> Enum.map(&(&1 * block_time_ms))

case Keyword.get(args, :log_file) do
  nil ->
    # Use custom formatter for prettier logs
    config :logger, :default_formatter, format: {ConsoleLogger, :format}, metadata: [:slot, :root]

  log_file ->
    # Log to file
    file = Path.expand(log_file)
    file |> Path.dirname() |> File.mkdir_p!()

    config :logger, :default_handler,
      config: [
        file: to_charlist(file),
        filesync_repeat_interval: 5000,
        file_check: 5000,
        max_no_bytes: 10_000_000,
        max_no_files: 5,
        compress_on_rotate: true
      ]

    # NOTE: We want to log UTC timestamps, for convenience
    config :logger, utc_log: true

    config :logger, :default_formatter,
      format: {LogfmtEx, :format},
      colors: [enabled: false],
      metadata: [:mfa]

    config :logfmt_ex, :opts,
      message_key: "msg",
      timestamp_key: "ts",
      timestamp_format: :iso8601
end
