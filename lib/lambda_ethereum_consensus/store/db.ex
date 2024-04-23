defmodule LambdaEthereumConsensus.Store.Db do
  @moduledoc """
  Module that handles the key-value store.
  """
  require Logger
  # TODO: replace GenServer with :ets
  use GenServer

  @registered_name __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @registered_name)
  end

  @spec put(binary, binary) :: :ok
  def put(key, value) do
    ref = GenServer.call(@registered_name, :get_ref)
    Exleveldb.put(ref, key, value)
  end

  @spec get(binary) :: {:ok, binary} | :not_found
  def get(key) do
    ref = GenServer.call(@registered_name, :get_ref)
    Exleveldb.get(ref, key)
  end

  @spec iterate() :: {:ok, :eleveldb.itr_ref()} | {:error, any()}
  def iterate() do
    ref = GenServer.call(@registered_name, :get_ref)
    # TODO: wrap cursor to make it DB-agnostic
    Exleveldb.iterator(ref, [])
  end

  @spec iterate_keys() :: {:ok, :eleveldb.itr_ref()} | {:error, any()}
  def iterate_keys() do
    ref = GenServer.call(@registered_name, :get_ref)
    # TODO: wrap cursor to make it DB-agnostic
    Exleveldb.iterator(ref, [], :keys_only)
  end

  @impl true
  def init(opts) do
    db_dir = Keyword.get(opts, :dir, get_dir())
    db_full_path = Path.expand(db_dir)
    File.mkdir_p!(db_full_path)
    {:ok, ref} = Exleveldb.open(db_full_path, create_if_missing: true)
    Logger.info("Opened database in '#{db_full_path}'")
    {:ok, %{ref: ref}}
  end

  @impl true
  def terminate(_reason, %{ref: ref}) do
    :ok = Exleveldb.close(ref)
  end

  # NOTE: LevelDB database ref usage is thread-safe
  @impl true
  def handle_call(:get_ref, _from, %{ref: ref} = state), do: {:reply, ref, state}

  defp get_dir() do
    Application.fetch_env!(:lambda_ethereum_consensus, __MODULE__)
    |> Keyword.fetch!(:dir)
  end
end
