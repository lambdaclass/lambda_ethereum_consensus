defmodule SszTypes.BeaconBlockBody do
  @moduledoc """
  Struct definition for `BeaconBlockBody`.
  Related definitions in `native/ssz_nif/src/types/`.
  """

  fields = [
    :randao_reveal,
    :eth1_data,
    :graffiti,
    :proposer_slashings,
    :attester_slashings,
    :attestations,
    :deposits,
    :voluntary_exits,
    :sync_aggregate,
    :execution_payload,
    :bls_to_execution_changes
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          randao_reveal: SszTypes.bls_signature(),
          eth1_data: SszTypes.Eth1Data.t(),
          graffiti: SszTypes.bytes32(),
          proposer_slashings: list(SszTypes.ProposerSlashing.t()),
          attester_slashings: list(SszTypes.AttesterSlashing.t()),
          attestations: list(SszTypes.Attestation.t()),
          deposits: list(SszTypes.Deposit.t()),
          voluntary_exits: list(SszTypes.VoluntaryExit.t()),
          sync_aggregate: SszTypes.SyncAggregate.t(),
          execution_payload: SszTypes.ExecutionPayload.t(),
          bls_to_execution_changes: list(SszTypes.BLSToExecutionChange.t())
        }
end
