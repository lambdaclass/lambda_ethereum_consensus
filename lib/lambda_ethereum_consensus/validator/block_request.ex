defmodule LambdaEthereumConsensus.Validator.BlockRequest do
  @moduledoc """
  Struct that stores and validates data for block construction.
  Most of the data is already validated when computing the state
  transition, so this focuses on cheap validations.
  """
  alias Types.BeaconState

  enforced_keys = [:slot, :proposer_index, :eth1_data]

  optional_keys = [
    graffiti_message: "",
    proposer_slashings: [],
    attester_slashings: [],
    attestations: [],
    voluntary_exits: [],
    bls_to_execution_changes: []
  ]

  @enforce_keys enforced_keys
  defstruct enforced_keys ++ optional_keys

  @type t() :: %__MODULE__{
          slot: Types.slot(),
          proposer_index: Types.validator_index(),
          graffiti_message: binary(),
          eth1_data: Types.Eth1Data.t(),
          proposer_slashings: [Types.ProposerSlashing.t()],
          attester_slashings: [Types.AttesterSlashing.t()],
          attestations: [Types.Attestation.t()],
          voluntary_exits: [Types.SignedVoluntaryExit.t()],
          bls_to_execution_changes: [Types.SignedBLSToExecutionChange.t()]
        }

  @spec validate(t(), BeaconState.t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{slot: slot}, %BeaconState{slot: state_slot}) when slot <= state_slot,
    do: {:error, "slot is older than the state"}

  def validate(%__MODULE__{} = request, _), do: {:ok, request}
end
