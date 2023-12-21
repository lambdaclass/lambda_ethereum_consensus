defmodule LambdaEthereumConsensus.StateTransition.Cache do
  @moduledoc """
  Caches expensive function calls.
  """

  @tables [
    :total_active_balance,
    :beacon_proposer_index,
    :active_validator_count,
    :beacon_committee
  ]

  @spec initialize_tables() :: :ok
  def initialize_tables do
    @tables |> Enum.each(&init_table/1)
  end

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
        value = compute_fun.()
        :ets.insert_new(table, {key, value})
        value
    end
  end
end
