import Config
alias LambdaEthereumConsensus.Beacon.StoreSetup
alias LambdaEthereumConsensus.ForkChoice
alias LambdaEthereumConsensus.SszEx
alias Types.BeaconStateDeneb

switches = [
  network: :string,
  checkpoint_sync_url: :string,
  execution_endpoint: :string,
  execution_jwt: :string,
  mock_execution: :boolean,
  mode: :string,
  datadir: :string,
  testnet_dir: :string,
  metrics: :boolean,
  metrics_port: :integer,
  log_file: :string,
  beacon_api: :boolean,
  beacon_api_port: :integer,
  validator_api: :boolean,
  validator_api_port: :integer,
  listen_address: [:string, :keep],
  discovery_port: :integer,
  boot_nodes: :string,
  keystore_dir: :string,
  keystore_pass_dir: :string
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
testnet_dir = Keyword.get(args, :testnet_dir)
metrics_port = Keyword.get(args, :metrics_port, nil)
enable_metrics = Keyword.get(args, :metrics, not is_nil(metrics_port))
beacon_api_port = Keyword.get(args, :beacon_api_port, nil)
enable_beacon_api = Keyword.get(args, :beacon_api, not is_nil(beacon_api_port))
validator_api_port = Keyword.get(args, :validator_api_port, nil)
enable_validator_api = Keyword.get(args, :validator_api, not is_nil(validator_api_port))
listen_addresses = Keyword.get_values(args, :listen_address)
discovery_port = Keyword.get(args, :discovery_port, 9000)
cli_bootnodes = Keyword.get(args, :boot_nodes, "")
keystore_dir = Keyword.get(args, :keystore_dir)
keystore_pass_dir = Keyword.get(args, :keystore_pass_dir)

if not is_nil(testnet_dir) and not is_nil(checkpoint_sync_url) do
  IO.puts("Both checkpoint sync and testnet url specified (only one should be specified).")
  System.halt(2)
end

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

# DB setup
default_datadir =
  case testnet_dir do
    nil -> "level_db/#{network}"
    _ -> "level_db/local_testnet"
  end

datadir = Keyword.get(args, :datadir, default_datadir)
File.mkdir_p!(datadir)
config :lambda_ethereum_consensus, LambdaEthereumConsensus.Store.Db, dir: datadir

# Network setup
{chain_config, bootnodes} =
  case testnet_dir do
    nil ->
      config = ConfigUtils.parse_config!(network)
      bootnodes = YamlElixir.read_from_file!("config/networks/#{network}/boot_enr.yaml")
      {config, bootnodes}

    testnet_dir ->
      Path.join(testnet_dir, "config.yaml") |> CustomConfig.load_from_file!()
      bootnodes = ConfigUtils.load_testnet_bootnodes(testnet_dir)
      {CustomConfig, bootnodes}
  end

# We use put_env here as we need this immediately after to read the state.
Application.put_env(:lambda_ethereum_consensus, ChainSpec, config: chain_config)

checkpoint_urls =
  case checkpoint_sync_url do
    urls when is_binary(urls) -> urls |> String.split(",") |> Enum.map(&String.trim/1)
    nil -> nil
  end

strategy = StoreSetup.make_strategy!(testnet_dir, checkpoint_urls)

genesis_validators_root =
  case strategy do
    {:file, state} -> state.genesis_validators_root
    _ -> chain_config.genesis_validators_root()
  end

config :lambda_ethereum_consensus, ChainSpec,
  config: chain_config,
  genesis_validators_root: genesis_validators_root

config :lambda_ethereum_consensus, StoreSetup, strategy: strategy

# Configures peer discovery
bootnodes =
  cli_bootnodes
  |> String.split(",")
  |> Enum.reject(&(&1 == ""))
  |> Enum.concat(bootnodes)

config :lambda_ethereum_consensus, :libp2p,
  port: discovery_port,
  bootnodes: bootnodes,
  listen_addr: listen_addresses

# Engine API

alias LambdaEthereumConsensus.Execution.EngineApi

mock_execution = Keyword.get(args, :mock_execution, mode == :db or is_nil(jwt_path))

implementation = if mock_execution, do: EngineApi.Mocked, else: EngineApi.Api
jwt_secret = if jwt_path, do: File.read!(jwt_path)

# Check that jwt secret is valid
if jwt_secret, do: LambdaEthereumConsensus.Execution.Auth.generate_token(jwt_secret)

config :lambda_ethereum_consensus, EngineApi,
  endpoint: execution_endpoint,
  jwt_secret: jwt_secret,
  implementation: implementation,
  version: "2.0"

# Beacon API
config :lambda_ethereum_consensus, BeaconApi.Endpoint,
  server: enable_beacon_api,
  # We use an infinit idle timeout to avoid closing sse connections, if needed we can
  # create a separate endpoint for them.
  http: [port: beacon_api_port || 4000, protocol_options: [idle_timeout: :infinity]],
  url: [host: "localhost"],
  render_errors: [
    formats: [json: BeaconApi.ErrorJSON],
    layout: false
  ]

# KeyStore API
config :lambda_ethereum_consensus, KeyStoreApi.Endpoint,
  server: enable_validator_api,
  http: [port: validator_api_port || 5000],
  url: [host: "localhost"],
  render_errors: [
    formats: [json: KeyStoreApi.ErrorJSON],
    layout: false
  ]

# Validator setup

if (keystore_dir != nil and keystore_pass_dir == nil) or
     (keystore_pass_dir !== nil and keystore_dir == nil) do
  IO.puts("Both keystore_dir and keystore_pass_dir must be provided.")
  System.halt(2)
end

if keystore_dir != nil and not File.dir?(keystore_dir) do
  IO.puts("Keystore directory not found: #{keystore_dir}")
  System.halt(2)
end

if keystore_pass_dir != nil and not File.dir?(keystore_pass_dir) do
  IO.puts("Keystore password directory not found: #{keystore_pass_dir}")
  System.halt(2)
end

config :lambda_ethereum_consensus, LambdaEthereumConsensus.ValidatorSet,
  keystore_dir: keystore_dir,
  keystore_pass_dir: keystore_pass_dir

# TODO: we should set this dynamically
block_time_ms =
  case network do
    "gnosis" -> 6000
    "mainnet" -> 12_000
    "sepolia" -> 100
    "holesky" -> 24_000
    "hoodi" -> 12_000
    # Default to mainnet
    _ -> 12_000
  end

# Metrics

config :lambda_ethereum_consensus, LambdaEthereumConsensus.PromEx,
  disabled: not enable_metrics,
  metrics_server: [
    port: metrics_port || 9568,
    auth_strategy: :none
  ]

config :lambda_ethereum_consensus, LambdaEthereumConsensus.PromExPlugin,
  block_processing_buckets: [0.5, 1.0, 1.5, 2, 4, 6, 8] |> Enum.map(&(&1 * block_time_ms)),
  poll_rate: 15_000

# Logging

case Keyword.get(args, :log_file) do
  nil ->
    # Use custom formatter for prettier logs
    config :logger, :default_formatter,
      format: {CustomConsoleLogger, :format},
      metadata: [:slot, :root, :bits]

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
      format: {CustomLogfmtEx, :format},
      colors: [enabled: false],
      metadata: [:mfa, :pid, :slot, :root]

    config :logfmt_ex, :opts,
      message_key: "msg",
      timestamp_key: "ts",
      timestamp_format: :iso8601
end

# Sentry
dsn = System.get_env("SENTRY_DSN")

if dsn do
  {git_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"])

  config :sentry, dsn: dsn, release: String.trim(git_sha)
end

# Peerbook penalization

penalizing_score =
  case network do
    "sepolia" -> 20
    "mainnet" -> 50
    _ -> 30
  end

config :lambda_ethereum_consensus, LambdaEthereumConsensus.P2P.Peerbook,
  penalizing_score: penalizing_score
