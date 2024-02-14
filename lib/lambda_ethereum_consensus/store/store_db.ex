defmodule LambdaEthereumConsensus.Store.StoreDb do
  @moduledoc """
  Beacon node store storage.
  """
  alias LambdaEthereumConsensus.Store.Db

  @store_prefix "store"

  @spec fetch_store() :: {:ok, Types.Store.t()} | :not_found
  def fetch_store do
    with {:ok, encoded_store} <- Db.get(@store_prefix) do
      {:ok, :erlang.binary_to_term(encoded_store)}
    end
  end

  @spec persist_store(Types.Store.t()) :: :ok
  def persist_store(%Types.Store{} = store) do
    # Compress the store before storing it. This doubles the time it takes to dump, but reduces size by 5 times.
    Db.put(@store_prefix, :erlang.term_to_binary(store, [{:compressed, 1}]))
  end
end
