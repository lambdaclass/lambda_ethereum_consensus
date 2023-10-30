defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  This module contains utility functions for handling operations
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.StateTransition.Mutators
  alias SszTypes.BeaconState

  @spec process_attester_slashing(BeaconState.t(), SszTypes.AttesterSlashing.t()) ::
          {:ok, BeaconState.t()} | {:error, any()}
  def process_attester_slashing(state, attester_slashing) do
    attestation_1 = attester_slashing.attestation_1
    attestation_2 = attester_slashing.attestation_2

    res = cond do
      not Predicates.is_slashable_attestation_data(attestation_1.data, attestation_2.data) -> {:ok, nil}
      not Predicates.is_valid_indexed_attestation(state, attestation_1) -> {:ok, nil}
      not Predicates.is_valid_indexed_attestation(state, attestation_2) -> {:ok, nil}
      true ->
        slashed_any = false

        {slashed_any, state} = Enum.uniq(attestation_1.attesting_indices)
        |> Enum.filter(fn i -> Enum.member?(attestation_2.attesting_indices, i) end)
        |> Enum.sort()
        |> Enum.reduce({slashed_any, state} , fn i, {slashed_any, state} ->
          res = cond do
              Predicates.is_slashable_validator(
              Enum.at(state.validators, i),
              Accessors.get_current_epoch(state)
            ) ->
              {:ok, state} = Mutators.slash_validator(state, i)
              {true, state}
            true -> {slashed_any, state}
            end
          res
        end)
        res = cond do
          not slashed_any -> {:ok, nil}
          true -> {:ok, state}
        end
        res
    end
    res
  end
end
