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

    cond do
      Predicates.is_slashable_attestation_data(attestation_1.data, attestation_2.data) == false -> {:ok, nil}
      Predicates.is_valid_indexed_attestation(state, attestation_1) == false -> {:ok, nil}
      Predicates.is_valid_indexed_attestation(state, attestation_2) == false -> {:ok, nil}
      true ->
        {slashed_any, state} =
        Enum.uniq(attestation_1.attesting_indices)
        |> Enum.filter(fn i -> Enum.member?(attestation_2.attesting_indices, i) end)
        |> Enum.sort()
        |> Enum.reduce_while({false, state} , fn i, {slashed_any, state} ->
          cond do
            Predicates.is_slashable_validator(
            Enum.at(state.validators, i),
            Accessors.get_current_epoch(state)
          ) ->
            case Mutators.slash_validator(state, i) do
              {:ok, state} -> {:cont, {true, state}}
              {:error, _msg} -> {:halt, {false, nil}}
            end
          true -> {:cont, {slashed_any, state}}
          end
        end)
        case slashed_any do
          false -> {:ok, nil}
          true -> {:ok, state}
        end
    end
  end
end
