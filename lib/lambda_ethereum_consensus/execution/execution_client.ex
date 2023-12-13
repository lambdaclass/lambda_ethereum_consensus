defmodule LambdaEthereumConsensus.Execution.ExecutionClient do
  @moduledoc """
  Execution Layer Engine API methods
  """

  use GenServer
  require Logger

  alias LambdaEthereumConsensus.Execution.Auth
  alias LambdaEthereumConsensus.Execution.EngineApi

  @type state :: %{
          jwt_secret: binary()
        }

  ##########################
  ### Public API
  ##########################

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def engine_exchange_capabilities do
    GenServer.call(__MODULE__, :engine_exchange_capabilities)
  end

  def forkchoice_updated(forkchoice_state, payload_attributes) do
    GenServer.call(__MODULE__, {:forkchoice_updated, forkchoice_state, payload_attributes})
  end

  @spec verify_and_notify_new_payload(any()) :: {:ok, true}
  def verify_and_notify_new_payload(_execution_payload) do
    # TODO: call engine api
    {:ok, true}
  end

  ##########################
  ### GenServer Callbacks
  ##########################

  @impl GenServer
  @spec init(any) :: {:ok, state()} | {:error, any}
  def init([engine_endpoint, jwt_path]) do
    if engine_endpoint do
      execution_config =
        Application.fetch_env!(
          :lambda_ethereum_consensus,
          LambdaEthereumConsensus.Execution.EngineApi
        )
        |> Keyword.put(:endpoint, engine_endpoint)

      Application.put_env(
        :lambda_ethereum_consensus,
        LambdaEthereumConsensus.Execution.EngineApi,
        execution_config
      )
    end

    jwt_secret =
      if jwt_path do
        case File.read(jwt_path) do
          {:ok, jwt_secret} ->
            jwt_secret

          {:error, reason} ->
            Logger.error("Failed to read jwt secret from #{jwt_path}. Reason: #{inspect(reason)}")

            System.stop(1)
        end
      else
        Logger.error(
          "No jwt file provided. Please specify the path to fetch it from via the --execution-jwt flag."
        )

        System.stop(1)
      end

    {:ok, %{jwt_secret: jwt_secret}}
  end

  @impl GenServer
  def handle_call(
        {:forkchoice_updated, forkchoice_state, payload_attributes},
        _from,
        state
      ) do
    {:ok, token, _} = Auth.generate_token(state.jwt_secret)

    result =
      EngineApi.engine_forkchoice_updated(token, forkchoice_state, payload_attributes)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(
        :engine_exchange_capabilities,
        _from,
        state
      ) do
    {:ok, token, _} = Auth.generate_token(state.jwt_secret)

    result =
      EngineApi.engine_exchange_capabilities(token)

    {:reply, result, state}
  end
end
