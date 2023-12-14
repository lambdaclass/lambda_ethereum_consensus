defmodule LambdaEthereumConsensus.StateTransition.Cache do
  @moduledoc """
  Caches expensive function calls.
  """

  alias LambdaEthereumConsensus.StateTransition.{Accessors, Misc}

  @spec init_cache_tables() :: :ok
  def init_cache_tables do
    [:total_active_balance, :beacon_proposer_index, :beacon_committee, :active_validator_count]
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
    root = get_epoch_root(state, epoch)

    lookup(:total_active_balance, {epoch, root}, compute_fun)
  rescue
    _ -> compute_fun.()
  end

  @spec cache_beacon_proposer_index(SszTypes.BeaconState.t(), (-> SszTypes.validator_index())) ::
          SszTypes.validator_index()
  def cache_beacon_proposer_index(%SszTypes.BeaconState{slot: slot} = state, compute_fun) do
    root = get_epoch_root(state)

    lookup(:beacon_proposer_index, {slot, root}, compute_fun)
  rescue
    _ -> compute_fun.()
  end

  @spec cache_beacon_committee(
          SszTypes.BeaconState.t(),
          SszTypes.slot(),
          SszTypes.commitee_index(),
          (-> list(SszTypes.validator_index()))
        ) ::
          list(SszTypes.validator_index())
  def cache_beacon_committee(state, slot, committee_index, compute_fun) do
    # PERF: compute all committees for the epoch
    epoch = Misc.compute_epoch_at_slot(slot)
    root = get_epoch_root(state, epoch)

    lookup(:beacon_committee, {slot, committee_index, root}, compute_fun)
  rescue
    _ -> compute_fun.()
  end

  @spec cache_active_validator_count(
          SszTypes.BeaconState.t(),
          SszTypes.epoch(),
          (-> SszTypes.uint64())
        ) ::
          SszTypes.uint64()
  def cache_active_validator_count(state, epoch, compute_fun) do
    lookup(:active_validator_count, {epoch, get_epoch_root(state)}, compute_fun)
  rescue
    _ -> compute_fun.()
  end

  defp get_epoch_root(state) do
    epoch = Accessors.get_current_epoch(state)
    get_epoch_root(state, epoch)
  end

  defp get_epoch_root(state, epoch) do
    {:ok, root} =
      epoch
      |> Misc.compute_start_slot_at_epoch()
      |> then(&Accessors.get_block_root_at_slot(state, &1 - 1))

    root
  end
end
