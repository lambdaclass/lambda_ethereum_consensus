defmodule LambdaEthereumConsensus.Validator.BlockRequest do
  @moduledoc """
  Struct that stores and validates data for block construction.
  """
  alias Types.BeaconState

  enforced_keys = [:slot, :proposer_index]

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

  @type t() :: %{
          slot: Types.slot(),
          proposer_index: Types.validator_index(),
          graffiti_message: binary()
        }

  @spec validate(t(), BeaconState.t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{slot: slot}, %BeaconState{slot: state_slot}) when slot <= state_slot,
    do: {:error, "slot is older than the state"}

  def validate(%__MODULE__{} = request, _), do: request
end
