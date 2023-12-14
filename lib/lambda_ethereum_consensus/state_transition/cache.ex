defmodule LambdaEthereumConsensus.StateTransition.Cache do
  @moduledoc """
  Caches expensive function calls.
  """

  alias LambdaEthereumConsensus.StateTransition.{Accessors, Misc}

  @spec init_cache_tables() :: :ok
  def init_cache_tables do
    :ets.new(__MODULE__, [:set, :public, :named_table])
    :ok
  end

  defp lookup(key, compute_fun) do
    case :ets.lookup(__MODULE__, key) do
      [{^key, balance}] ->
        balance

      [] ->
        balance = compute_fun.()
        :ets.insert_new(__MODULE__, {key, balance})
        balance
    end
  end

  @spec cache_total_active_balance(SszTypes.BeaconState.t(), (-> SszTypes.gwei())) ::
          SszTypes.gwei()
  def cache_total_active_balance(state, compute_fun) do
    epoch = Accessors.get_current_epoch(state)

    {:ok, root} =
      Accessors.get_block_root_at_slot(state, Misc.compute_start_slot_at_epoch(epoch) - 1)

    lookup({epoch, root}, compute_fun)
  rescue
    _ -> compute_fun.()
  end
end
