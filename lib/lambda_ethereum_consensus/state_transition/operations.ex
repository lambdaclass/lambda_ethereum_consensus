defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  This module contains utility functions for handling operations
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.StateTransition.Mutators
  alias SszTypes.BeaconState

  @spec process_attester_slashing(BeaconState.t(), SszTypes.AttesterSlashing.t()) ::
          {:ok} | {:error, any()}
  def process_attester_slashing(state, attester_slashing) do
    attestation_1 = attester_slashing.attestation_1
    attestation_2 = attester_slashing.attestation_2

    if not Predicates.is_slashable_attestation_data(attestation_1.data, attestation_2.data),
      do: {:error, "Attestation data is not slashable."}

    if not Predicates.is_valid_indexed_attestation(state, attestation_1),
      do: {:error, "Indexed attestation is not valid for attestation1."}

    if not Predicates.is_valid_indexed_attestation(state, attestation_2),
      do: {:error, "Indexed attestation is not valid for attestation2."}

    slashed_any = false

    indices =
      Enum.uniq(attestation_1.attesting_indices)
      |> Enum.filter(fn i -> Enum.member?(attestation_2.attesting_indices, i) end)
      |> Enum.sort()
      |> Enum.each(fn i ->
        if(
          Predicates.is_slashable_validator(
            Enum.at(state.validators, i),
            Accessors.get_current_epoch(state)
          )
        )

        Mutators.slash_validator(state, i)
        slashed_any = true
      end)

    if not slashed_any, do: {:error, "Didn't slash any."}
    {:ok}
  end
end
