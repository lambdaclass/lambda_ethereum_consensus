defmodule MinimalConfig do
  @moduledoc """
  Minimal test configuration.
  """

  @type_equivalence %{
    "HistoricalBatch" => "HistoricalBatchMinimal",
    "SyncAggregate" => "SyncAggregateMinimal",
    "BeaconBlockBody" => "BeaconBlockBodyMinimal"
  }

  def get_handler_mapping, do: @type_equivalence
end
