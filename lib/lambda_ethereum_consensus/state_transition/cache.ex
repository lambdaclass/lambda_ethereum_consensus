defmodule LambdaEthereumConsensus.StateTransition.Cache do
  @moduledoc """
  Caches expensive function calls.
  """

  @spec init_table(:ets.table()) :: :ok
  def init_table(table) do
    :ets.new(table, [:set, :public, :named_table])
    :ok
  end

  @spec lazily_compute(:ets.table(), key :: any(), (-> value :: any())) :: value :: any()
  def lazily_compute(table, key, compute_fun) do
    if :ets.info(table) == :undefined do
      init_table(table)
    end

    case :ets.lookup(table, key) do
      [{^key, balance}] ->
        balance

      [] ->
        balance = compute_fun.()
        :ets.insert_new(table, {key, balance})
        balance
    end
  end
end
