defmodule MainnetConfig do
  @moduledoc """
  Mainnet test configuration.
  """

  @type_equivalence %{
    "HistoricalBatch" => "HistoricalBatchMainnet",
    "PendingAttestation" => "PendingAttestationMainnet",
    "ExecutionPayloadHeader" => "ExecutionPayloadHeaderMainnet",
    "ExecutionPayload" => "ExecutionPayloadMainnet"
  }

  def get_handler_mapping, do: @type_equivalence
end
