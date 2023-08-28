defmodule MinimalConfig do
  @moduledoc """
  Minimal test configuration.
  """

  @type_equivalence %{
    "HistoricalBatch" => "HistoricalBatchMinimal",
    "PendingAttestation" => "PendingAttestationMainnet",
    "ExecutionPayload" => "ExecutionPayloadMinimal",
    "ExecutionPayloadHeader" => "ExecutionPayloadHeaderMinimal"
  }

  def get_handler_mapping, do: @type_equivalence
end
