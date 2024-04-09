defmodule LambdaEthereumConsensus.Validator.BlockRequest do
  @moduledoc """
  Struct that stores and validates data for block construction.
  Most of the data is already validated when computing the state
  transition, so this focuses on cheap validations.
  """
  alias Types.BeaconState

  enforced_keys = [:slot, :proposer_index, :parent_root, :privkey]

  optional_keys = [
    graffiti_message: "",
    proposer_slashings: [],
    attester_slashings: [],
    attestations: [],
    voluntary_exits: [],
    bls_to_execution_changes: [],
    eth1_data: nil,
    execution_payload: nil
  ]

  @enforce_keys enforced_keys
  defstruct enforced_keys ++ optional_keys

  @type t() :: %__MODULE__{
          slot: Types.slot(),
          parent_root: Types.root(),
          proposer_index: Types.validator_index(),
          graffiti_message: binary(),
          proposer_slashings: [Types.ProposerSlashing.t()],
          attester_slashings: [Types.AttesterSlashing.t()],
          attestations: [Types.Attestation.t()],
          voluntary_exits: [Types.SignedVoluntaryExit.t()],
          bls_to_execution_changes: [Types.SignedBLSToExecutionChange.t()],
          privkey: Bls.privkey()
        }

  @spec validate(t(), BeaconState.t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{slot: slot}, %BeaconState{slot: state_slot}) when slot <= state_slot,
    do: {:error, "slot is older than the state"}

  def validate(%__MODULE__{graffiti_message: message} = request, state)
      when byte_size(message) != 32 do
    %{request | graffiti_message: pad_graffiti_message(message)} |> validate(state)
  end

  def validate(%__MODULE__{} = request, _), do: {:ok, request}

  @spec pad_graffiti_message(binary()) :: <<_::256>>
  defp pad_graffiti_message(message) do
    # Truncate to 32 bytes
    message = binary_slice(message, 0, 32)
    # Pad to 32 bytes
    padding_len = 256 - bit_size(message)
    <<message::binary, 0::size(padding_len)>>
  end
end
