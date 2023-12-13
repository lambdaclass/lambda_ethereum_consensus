defmodule LambdaEthereumConsensus.StateTransition.Cache do
  @moduledoc """
  Caches expensive function calls.
  """

  @spec init_cache_tables() :: :ok
  def init_cache_tables do
    :ets.new(__MODULE__, [:set, :public, :named_table])
    :ok
  end

  @spec cache_total_active_balance(SszTypes.epoch(), (-> SszTypes.gwei())) :: SszTypes.gwei()
  def cache_total_active_balance(epoch, compute_fun) do
    case :ets.lookup(__MODULE__, epoch) do
      [{^epoch, balance}] ->
        balance

      [] ->
        balance = compute_fun.()
        :ets.insert_new(__MODULE__, {epoch, balance})
        balance
    end
  rescue
    _ -> compute_fun.()
  end
end
