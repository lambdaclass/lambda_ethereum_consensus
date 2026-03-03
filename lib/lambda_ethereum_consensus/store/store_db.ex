defmodule LambdaEthereumConsensus.Store.StoreDb do
  @moduledoc """
  Beacon node store storage.
  """
  alias LambdaEthereumConsensus.Store.Db
  alias Types.Store

  @store_prefix "store"

  @spec fetch_store() :: {:ok, Types.Store.t()} | :not_found
  def fetch_store() do
    :telemetry.span([:db, :latency], %{}, fn ->
      {get(@store_prefix), %{module: "fork_choice", action: "fetch"}}
    end)
  end

  @spec persist_store(Types.Store.t()) :: :ok
  def persist_store(%Types.Store{} = store) do
    :telemetry.span([:db, :latency], %{}, fn ->
      {put(@store_prefix, Store.remove_cache(store)), %{module: "fork_choice", action: "persist"}}
    end)
  end

  @spec fetch_genesis_time() :: {:ok, Types.uint64()} | :not_found
  def fetch_genesis_time() do
    with {:ok, store} <- fetch_store() do
      store.genesis_time
    end
  end

  @spec fetch_genesis_time!() :: Types.uint64()
  def fetch_genesis_time!() do
    {:ok, %{genesis_time: genesis_time}} = fetch_store()
    genesis_time
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
