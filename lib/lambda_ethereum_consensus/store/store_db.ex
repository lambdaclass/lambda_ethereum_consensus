defmodule LambdaEthereumConsensus.Store.StoreDb do
  @moduledoc """
  Beacon node store storage.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias Types.Store

  @store_prefix "store"
  @genesis_time_key {__MODULE__, :genesis_time}

  @spec fetch_store() :: {:ok, Types.Store.t()} | :not_found
  def fetch_store() do
    :telemetry.span([:db, :latency], %{}, fn ->
      {get(@store_prefix), %{module: "fork_choice", action: "fetch"}}
    end)
  end

  @spec persist_store(Types.Store.t()) :: :ok
  def persist_store(%Types.Store{} = store) do
    # Cache genesis_time in persistent_term for fast access.
    # This avoids deserializing the entire store just to read genesis_time.
    cache_genesis_time(store.genesis_time)

    :telemetry.span([:db, :latency], %{}, fn ->
      {put(@store_prefix, Store.remove_cache(store)), %{module: "fork_choice", action: "persist"}}
    end)
  end

  @spec fetch_genesis_time() :: {:ok, Types.uint64()} | :not_found
  def fetch_genesis_time() do
    case cached_genesis_time() do
      nil ->
        with {:ok, store} <- fetch_store() do
          cache_genesis_time(store.genesis_time)
          store.genesis_time
        end

      time ->
        {:ok, time}
    end
  end

  @spec fetch_genesis_time!() :: Types.uint64()
  def fetch_genesis_time!() do
    case cached_genesis_time() do
      nil ->
        {:ok, %{genesis_time: genesis_time}} = fetch_store()
        cache_genesis_time(genesis_time)
        genesis_time

      time ->
        time
    end
  end

  defp cached_genesis_time do
    :persistent_term.get(@genesis_time_key, nil)
  end

  defp cache_genesis_time(genesis_time) do
    :persistent_term.put(@genesis_time_key, genesis_time)
  end

  defp get(key) do
    with {:ok, value} <- Db.get(key) do
      {:ok, :erlang.binary_to_term(value)}
    end
  end

  defp put(key, value) do
    # Compress before storing. This doubles the time it takes to dump, but reduces size by 5 times.
    Db.put(key, :erlang.term_to_binary(value, [{:compressed, 1}]))
  end
end
