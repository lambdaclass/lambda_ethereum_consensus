defmodule Types.BeaconBlockBodyDeneb do
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
    :bls_to_execution_changes,
    :blob_kzg_commitments
  ]

  @enforce_keys fields
  defstruct fields

  @type t :: %__MODULE__{
          randao_reveal: Types.bls_signature(),
          eth1_data: Types.Eth1Data.t(),
          graffiti: Types.bytes32(),
          # max MAX_PROPOSER_SLASHINGS
          proposer_slashings: list(Types.ProposerSlashing.t()),
          # max MAX_ATTESTER_SLASHINGS
          attester_slashings: list(Types.AttesterSlashing.t()),
          # max MAX_ATTESTATIONS
          attestations: list(Types.Attestation.t()),
          # max MAX_DEPOSITS
          deposits: list(Types.Deposit.t()),
          # max MAX_VOLUNTARY_EXITS
          voluntary_exits: list(Types.VoluntaryExit.t()),
          sync_aggregate: Types.SyncAggregate.t(),
          execution_payload: Types.ExecutionPayloadDeneb.t(),
          # max MAX_BLS_TO_EXECUTION_CHANGES
          bls_to_execution_changes: list(Types.BLSToExecutionChange.t()),
          # max MAX_BLOB_COMMITMENTS_PER_BLOCK
          blob_kzg_commitments: list(Types.kzg_commitment())
        }

  @impl LambdaEthereumConsensus.Container
  def schema do
    [
      {:randao_reveal, TypeAliases.bls_signature()},
      {:eth1_data, Types.Eth1Data},
      {:graffiti, TypeAliases.bytes32()},
      {:proposer_slashings,
       {:list, Types.ProposerSlashing, ChainSpec.get("MAX_PROPOSER_SLASHINGS")}},
      {:attester_slashings,
       {:list, Types.AttesterSlashing, ChainSpec.get("MAX_ATTESTER_SLASHINGS")}},
      {:attestations, {:list, Types.Attestation, ChainSpec.get("MAX_ATTESTATIONS")}},
      {:deposits, {:list, Types.Deposit, ChainSpec.get("MAX_DEPOSITS")}},
      {:voluntary_exits,
       {:list, Types.SignedVoluntaryExit, ChainSpec.get("MAX_VOLUNTARY_EXITS")}},
      {:sync_aggregate, Types.SyncAggregate},
      {:execution_payload, Types.ExecutionPayloadDeneb},
      {:bls_to_execution_changes,
       {:list, Types.SignedBLSToExecutionChange, ChainSpec.get("MAX_BLS_TO_EXECUTION_CHANGES")}},
      {:blob_kzg_commitments,
       {:list, TypeAliases.kzg_commitment(), ChainSpec.get("MAX_BLOB_COMMITMENTS_PER_BLOCK")}}
    ]
  end
end
