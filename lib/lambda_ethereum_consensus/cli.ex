defmodule LambdaEthereumConsensus.Cli do
  @moduledoc """
  Processes command line arguments
  """
  require Logger
  alias LambdaEthereumConsensus.Execution.EngineApi

  def parse_args do
    {args, _remaining_args, _errors} =
      OptionParser.parse(System.argv(),
        switches: [
          network: :string,
          checkpoint_sync: :string,
          execution_endpoint: :string,
          execution_jwt: :string
        ]
      )

    init_config_spec(Keyword.get(args, :network, "mainnet"))

    init_engine_api_config(
      Keyword.get(args, :execution_endpoint),
      Keyword.get(args, :execution_jwt)
    )

    args
  end

  def init_config_spec(network) do
    config_spec =
      case network do
        "minimal" ->
          MinimalConfig

        "mainnet" ->
          MainnetConfig

        _ ->
          Logger.error(
            "Invalid network provided. Please specify a valid network via the --network flag."
          )

          System.stop(1)
      end

    Application.put_env(
      :lambda_ethereum_consensus,
      ChainSpec,
      config: config_spec
    )

    bootnodes = YamlElixir.read_from_file!("config/networks/#{network}/bootnodes.yaml")

    Application.fetch_env!(:lambda_ethereum_consensus, :discovery)
    |> Keyword.put(:bootnodes, bootnodes)
    |> then(&Application.put_env(:lambda_ethereum_consensus, :discovery, &1))
  end

  defp init_engine_api_config(endpoint, nil) do
    Logger.warning(
      "No jwt file provided. Please specify the path to fetch it from via the --execution-jwt flag."
    )

    Application.fetch_env!(:lambda_ethereum_consensus, EngineApi)
    |> then(&if endpoint, do: Keyword.put(&1, :endpoint, endpoint), else: &1)
    |> then(&Application.put_env(:lambda_ethereum_consensus, EngineApi, &1))
  end

  defp init_engine_api_config(endpoint, jwt_path) do
    jwt_secret =
      case File.read(jwt_path) do
        {:ok, jwt_secret} ->
          jwt_secret

        {:error, reason} ->
          Logger.error("Failed to read jwt secret from #{jwt_path}. Reason: #{inspect(reason)}")

          System.stop(1)
      end

    execution_config =
      Application.fetch_env!(:lambda_ethereum_consensus, EngineApi)
      |> Keyword.put(:jwt_secret, jwt_secret)
      |> then(
        &if endpoint do
          Keyword.put(&1, :endpoint, endpoint)
        else
          &1
        end
      )

    Application.put_env(
      :lambda_ethereum_consensus,
      EngineApi,
      execution_config
    )
  end
end
