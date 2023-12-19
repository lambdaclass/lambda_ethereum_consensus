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
          checkpoint_sync: :string,
          execution_endpoint: :string,
          execution_jwt: :string
        ]
      )

    init_engine_api_config(
      Keyword.get(args, :execution_endpoint),
      Keyword.get(args, :execution_jwt)
    )

    args
  end

  defp init_engine_api_config(_endpoint, nil) do
    Logger.error(
      "No jwt file provided. Please specify the path to fetch it from via the --execution-jwt flag."
    )

    System.stop(1)
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
