defmodule MainnetConfig do
  @moduledoc """
  Mainnet test configuration.
  """

  @type_equivalence %{
    "HistoricalBatch" => "HistoricalBatchMainnet",
    "PendingAttestation" => "PendingAttestationMainnet",
    "Attestation" => "AttestationMainnet"
  }

  def get_handler_mapping, do: @type_equivalence
end
