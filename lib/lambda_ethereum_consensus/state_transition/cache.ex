defmodule LambdaEthereumConsensus.StateTransition.Cache do
  @moduledoc """
  Caches expensive function calls.
  """
  require Ex2ms

  @tables [
    # k = {epoch, root} ; v = int
    :total_active_balance,
    # k = {slot, root} ; v = int
    :beacon_proposer_index,
    # k = {epoch, root} ; v = int
    :active_validator_count,
    # k = {slot, {index, root}} ; v = [index]
    :beacon_committee,
    # k = {epoch, root} ; v = Aja.vec(index)
    :active_validator_indices
  ]

  @epoch_retain_window 3

  defp cleanup_epoch_ms(key) do
    (elem(key, 0) - @epoch_retain_window) |> max(0) |> ms_less_than()
  end

  defp cleanup_slot_ms(key) do
    (elem(key, 0) - @epoch_retain_window * ChainSpec.get("SLOTS_PER_EPOCH"))
    |> max(0)
    |> ms_less_than()
  end

  defp ms_less_than(const) do
    # NOTE: no need to specify false clause
    # This match-spec returns true for tuples with epoch/slot smaller than `const`
    Ex2ms.fun do
      {{x, _}} when x < ^const -> true
    end
  end

  defp generate_cleanup_spec(:total_active_balance, key), do: cleanup_epoch_ms(key)
  defp generate_cleanup_spec(:beacon_proposer_index, key), do: cleanup_slot_ms(key)
  defp generate_cleanup_spec(:active_validator_count, key), do: cleanup_epoch_ms(key)
  defp generate_cleanup_spec(:beacon_committee, key), do: cleanup_slot_ms(key)
  defp generate_cleanup_spec(:active_validator_indices, key), do: cleanup_epoch_ms(key)

  @spec initialize_cache() :: :ok
  def initialize_cache(), do: @tables |> Enum.each(&init_table/1)

  @spec clear_cache() :: :ok
  def clear_cache(), do: @tables |> Enum.each(&:ets.delete_all_objects/1)

  @spec init_table(:ets.table()) :: :ok
  def init_table(table) do
    :ets.new(table, [:set, :public, :named_table])
    :ok
  end

  @spec lazily_compute(:ets.table(), key :: any(), (-> value :: any())) :: value :: any()
  def lazily_compute(table, key, compute_fun) do
    case :ets.lookup(table, key) do
      [{^key, value}] ->
        value

      [] ->
        clean_up_old_entries(table, key)
        value = compute_fun.()
        :ets.insert_new(table, {key, value})
        value
    end
  end

  defp clean_up_old_entries(table, key) do
    match_spec = generate_cleanup_spec(table, key)
    :ets.select_delete(table, match_spec)
  end
end
