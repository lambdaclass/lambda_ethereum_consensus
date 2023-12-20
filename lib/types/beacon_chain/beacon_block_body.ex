defmodule Types.BeaconBlockBody do
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
          randao_reveal: Types.bls_signature(),
          eth1_data: Types.Eth1Data.t(),
          graffiti: Types.bytes32(),
          proposer_slashings: list(Types.ProposerSlashing.t()),
          attester_slashings: list(Types.AttesterSlashing.t()),
          attestations: list(Types.Attestation.t()),
          deposits: list(Types.Deposit.t()),
          voluntary_exits: list(Types.VoluntaryExit.t()),
          sync_aggregate: Types.SyncAggregate.t(),
          execution_payload: Types.ExecutionPayload.t(),
          bls_to_execution_changes: list(Types.BLSToExecutionChange.t())
        }
end
