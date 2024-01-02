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
          randao_reveal: Types.bls_signature(),
          eth1_data: Types.Eth1Data.t(),
          graffiti: Types.bytes32(),
          # max 16
          proposer_slashings: list(Types.ProposerSlashing.t()),
          # max 2
          attester_slashings: list(Types.AttesterSlashing.t()),
          # max 128
          attestations: list(Types.Attestation.t()),
          # max 16
          deposits: list(Types.Deposit.t()),
          # max 16
          voluntary_exits: list(Types.VoluntaryExit.t()),
          sync_aggregate: Types.SyncAggregate.t(),
          execution_payload: Types.ExecutionPayload.t(),
          # max 16
          bls_to_execution_changes: list(Types.BLSToExecutionChange.t())
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:randao_reveal, {:bytes, 96}},
      {:eth1_data, Types.Eth1Data},
      {:graffiti, {:bytes, 32}},
      {:proposer_slashings, {:list, Types.ProposerSlashing, 16}},
      {:attester_slashings, {:list, Types.AttesterSlashing, 2}},
      {:attestations, {:list, Types.Attestation, 128}},
      {:deposits, {:list, Types.Deposit, 16}},
      {:voluntary_exits, {:list, Types.VoluntaryExit, 16}},
      {:sync_aggregate, Types.SyncAggregate},
      {:execution_payload, Types.ExecutionPayload},
      {:bls_to_execution_changes, {:list, Types.BLSToExecutionChange, 16}}
    ]
  end
end
