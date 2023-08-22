defmodule MinimalConfig do
  @moduledoc """
  Minimal test configuration.
  """

  @type_equivalence %{
    "HistoricalBatch" => "HistoricalBatchMinimal",
    "IndexedAttestation" => "IndexedAttestationMainnet",
    "PendingAttestation" => "PendingAttestationMainnet"
  }

  def get_handler_mapping(), do: @type_equivalence
end
