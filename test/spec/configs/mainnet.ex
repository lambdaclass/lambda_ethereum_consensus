defmodule MainnetConfig do
  @moduledoc """
  Mainnet test configuration.
  """

  @type_equivalence %{
    "HistoricalBatch" => "HistoricalBatchMainnet",
    "IndexedAttestation" => "IndexedAttestationMainnet",
    "PendingAttestation" => "PendingAttestationMainnet"
  }

  def get_handler_mapping, do: @type_equivalence
end
