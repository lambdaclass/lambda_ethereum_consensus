defmodule LambdaEthereumConsensus.Store.Db do
  @moduledoc """
  Module that handles the key-value store.
  """

  use GenServer

  @registered_name __MODULE__
  @db_location "level_db"

  def start_link(_) do
    GenServer.start_link(__MODULE__, @db_location, name: @registered_name)
  end

  @spec put(binary, binary) :: :ok
  def put(key, value) do
    GenServer.call(@registered_name, {:put, {key, value}})
    :ok
  end

  @spec get(binary) :: :not_found | {:error, binary} | {:ok, binary}
  def get(key) do
    GenServer.call(@registered_name, {:get, key})
  end

  @impl true
  def init(db_location) do
    {:ok, ref} = Exleveldb.open(db_location, create_if_missing: true)
    {:ok, [ref: ref]}
  end

  @impl true
  def terminate(_reason, state) do
    [ref: ref] = state
    :ok = Exleveldb.close(ref)
  end

  @impl true
  def handle_call({:put, {key, value}}, _from, state) do
    [ref: ref] = state
    :ok = Exleveldb.put(ref, key, value)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    [ref: ref] = state

    case Exleveldb.get(ref, key) do
      {:ok, value} ->
        {:reply, {:ok, value}, state}

      :not_found ->
        {:reply, :not_found, state}
    end
  end
end
