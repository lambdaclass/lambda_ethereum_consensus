defmodule LambdaEthereumConsensus.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  alias LambdaEthereumConsensus.Store.CheckpointStates

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Configure sentry logger handler
    Logger.add_handlers(:lambda_ethereum_consensus)
    mode = get_operation_mode()

    check_jwt_secret(mode)

    children = get_children(mode)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LambdaEthereumConsensus.Supervisor]

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeaconApi.Endpoint.config_change(changed, removed)
    KeyStoreApi.Endpoint.config_change(changed, removed)
    :ok
  end

  defp get_children(:mixed) do
    CheckpointStates.new()

    [
      LambdaEthereumConsensus.Store.Db,
      LambdaEthereumConsensus.Store.Blocks,
      LambdaEthereumConsensus.Store.BlockStates
    ]
  end

  defp get_children(:db) do
    get_children(:mixed) ++
      [
        {Task.Supervisor, name: StoreStatesSupervisor}
      ]
  end

  defp get_children(:full) do
    get_children(:mixed) ++
      [
        BeaconApi.Endpoint,
        KeyStoreApi.Endpoint,
        LambdaEthereumConsensus.PromEx,
        LambdaEthereumConsensus.Beacon.BeaconNode
      ]
  end

  defp get_operation_mode() do
    Application.fetch_env!(:lambda_ethereum_consensus, LambdaEthereumConsensus)
    |> Keyword.fetch!(:mode)
  end

  defp check_jwt_secret(:db), do: nil

  defp check_jwt_secret(:full) do
    jwt_secret =
      Application.fetch_env!(
        :lambda_ethereum_consensus,
        LambdaEthereumConsensus.Execution.EngineApi
      )
      |> Keyword.fetch!(:jwt_secret)

    if is_nil(jwt_secret) do
      Logger.warning(
        "[EngineAPI] A JWT secret is needed for communication with the execution engine. " <>
          "Please specify the file to load it from with the --execution-jwt flag."
      )
    end
  end
end
