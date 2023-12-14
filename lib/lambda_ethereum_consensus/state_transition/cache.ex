defmodule LambdaEthereumConsensus.StateTransition.Cache do
  @moduledoc """
  Caches expensive function calls.
  """

  alias LambdaEthereumConsensus.StateTransition.{Accessors, Misc}

  @spec init_cache_tables() :: :ok
  def init_cache_tables do
    [:total_active_balance, :beacon_proposer_index]
    |> Enum.each(fn table ->
      :ets.new(table, [:set, :public, :named_table])
    end)
  end

  defp lookup(table, key, compute_fun) do
    case :ets.lookup(table, key) do
      [{^key, balance}] ->
        balance

      [] ->
        balance = compute_fun.()
        :ets.insert_new(table, {key, balance})
        balance
    end
  end

  @spec cache_total_active_balance(SszTypes.BeaconState.t(), (-> SszTypes.gwei())) ::
          SszTypes.gwei()
  def cache_total_active_balance(state, compute_fun) do
    epoch = Accessors.get_current_epoch(state)

    {:ok, root} =
      Accessors.get_block_root_at_slot(state, Misc.compute_start_slot_at_epoch(epoch) - 1)

    lookup(:total_active_balance, {epoch, root}, compute_fun)
  rescue
    _ -> compute_fun.()
  end

  @spec cache_beacon_proposer_index(SszTypes.BeaconState.t(), (-> SszTypes.validator_index())) ::
          SszTypes.validator_index()
  def cache_beacon_proposer_index(%SszTypes.BeaconState{slot: slot} = state, compute_fun) do
    epoch = Accessors.get_current_epoch(state)

    {:ok, root} =
      Accessors.get_block_root_at_slot(state, Misc.compute_start_slot_at_epoch(epoch) - 1)

    lookup(:beacon_proposer_index, {slot, root}, compute_fun)
  rescue
    _ -> compute_fun.()
  end
end
