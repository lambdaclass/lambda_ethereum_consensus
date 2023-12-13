defmodule SszTypes.BeaconBlockBody do
  @moduledoc """
  Struct definition for `BeaconBlockBody`.
  Related definitions in `native/ssz_nif/src/types/`.
  """
  @behaviour LambdaEthereumConsensus.Container

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
          # max 16
          proposer_slashings: list(SszTypes.ProposerSlashing.t()),
          # max 2
          attester_slashings: list(SszTypes.AttesterSlashing.t()),
          # max 128
          attestations: list(SszTypes.Attestation.t()),
          # max 16
          deposits: list(SszTypes.Deposit.t()),
          # max 16
          voluntary_exits: list(SszTypes.VoluntaryExit.t()),
          sync_aggregate: SszTypes.SyncAggregate.t(),
          execution_payload: SszTypes.ExecutionPayload.t(),
          # max 16
          bls_to_execution_changes: list(SszTypes.BLSToExecutionChange.t())
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:randao_reveal, {:bytes, 96}},
      {:eth1_data, SszTypes.Eth1Data},
      {:graffiti, {:bytes, 32}},
      {:proposer_slashings, {:list, SszTypes.ProposerSlashing, 16}},
      {:attester_slashings, {:list, SszTypes.AttesterSlashing, 2}},
      {:attestations, {:list, SszTypes.Attestation, 128}},
      {:deposits, {:list, SszTypes.Deposit, 16}},
      {:voluntary_exits, {:list, SszTypes.VoluntaryExit, 16}},
      {:sync_aggregate, SszTypes.SyncAggregate},
      {:execution_payload, SszTypes.ExecutionPayload},
      {:bls_to_execution_changes, {:list, SszTypes.BLSToExecutionChange, 16}}
    ]
  end
end
