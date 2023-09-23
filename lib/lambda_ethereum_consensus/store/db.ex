defmodule LambdaEthereumConsensus.Store.Db do
  @moduledoc """
  Module that handles the key-value store.
  """
  # TODO: replace GenServer with :ets
  use GenServer

  @registered_name __MODULE__
  @db_location "level_db"

  def start_link(_) do
    GenServer.start_link(__MODULE__, @db_location, name: @registered_name)
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

  @spec iterate_keys() :: {:ok, :eleveldb.itr_ref()} | {:error, any()}
  def iterate_keys do
    ref = GenServer.call(@registered_name, :get_ref)
    # TODO: wrap cursor to make it DB-agnostic
    Exleveldb.iterator(ref, [], :keys_only)
  end

  @impl true
  def init(db_location) do
    {:ok, ref} = Exleveldb.open(db_location, create_if_missing: true)
    {:ok, %{ref: ref}}
  end

  @impl true
  def terminate(_reason, %{ref: ref}) do
    :ok = Exleveldb.close(ref)
  end

  # NOTE: LevelDB database ref usage is thread-safe
  @impl true
  def handle_call(:get_ref, _from, %{ref: ref} = state), do: {:reply, ref, state}
end
