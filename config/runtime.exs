# General application configuration
import Config

config :lambda_ethereum_consensus, :mainnet_capella_presets,
  YamlElixir.read_from_file!("config/presets/mainnet/capella.yaml") |> SpecTestUtils.parse_yaml()

config :lambda_ethereum_consensus, :minimal_capella_presets,
  YamlElixir.read_from_file!("config/presets/minimal/capella.yaml") |> SpecTestUtils.parse_yaml()
