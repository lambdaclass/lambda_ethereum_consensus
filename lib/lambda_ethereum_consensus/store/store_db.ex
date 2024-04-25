defmodule LambdaEthereumConsensus.Store.StoreDb do
  @moduledoc """
  Beacon node store storage.
  """
  alias LambdaEthereumConsensus.Store.Db

  @store_prefix "store"
  @snapshot_prefix "snapshot"

  @spec fetch_store() :: {:ok, Types.Store.t()} | :not_found
  def fetch_store(), do: get(@store_prefix)

  @spec persist_store(Types.Store.t()) :: :ok
  def persist_store(%Types.Store{} = store) do
    put(@store_prefix, store)
  end

  @spec fetch_deposits_snapshot() :: {:ok, Types.DepositTreeSnapshot.t()} | :not_found
  def fetch_deposits_snapshot(), do: get(@snapshot_prefix)

  @spec persist_deposits_snapshot(Types.DepositTreeSnapshot.t()) :: :ok
  def persist_deposits_snapshot(%Types.DepositTreeSnapshot{} = snapshot) do
    put(@snapshot_prefix, snapshot)
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
