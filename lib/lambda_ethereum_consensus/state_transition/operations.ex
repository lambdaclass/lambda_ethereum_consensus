defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  State transition Operations related functions
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias SszTypes.BeaconState
  alias SszTypes.ExecutionPayload
  alias SszTypes.Validator
  alias SszTypes.Withdrawal

  @doc """
  Apply withdrawals to the state.
  """
  @spec process_withdrawals(BeaconState.t(), ExecutionPayload.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_withdrawals(
        %BeaconState{
          validators: validators
        } = state,
        %ExecutionPayload{withdrawals: withdrawals}
      ) do
    expected_withdrawals = get_expected_withdrawals(state)

    length_of_validators = length(validators)

    with {:ok, state} <- decrease_balances(state, withdrawals, expected_withdrawals) do
      {:ok,
       state
       |> update_next_withdrawal_index(expected_withdrawals)
       |> update_next_withdrawal_validator_index(expected_withdrawals, length_of_validators)}
    end
  end

  @spec update_next_withdrawal_index(BeaconState.t(), list(Withdrawal.t())) :: BeaconState.t()
  defp update_next_withdrawal_index(state, expected_withdrawals) do
    # Update the next withdrawal index if this block contained withdrawals
    length_of_expected_withdrawals = length(expected_withdrawals)

    case length_of_expected_withdrawals != 0 do
      true ->
        latest_withdrawal = List.last(expected_withdrawals)
        %BeaconState{state | next_withdrawal_index: latest_withdrawal.index + 1}

      false ->
        state
    end
  end

  @spec update_next_withdrawal_validator_index(BeaconState.t(), list(Withdrawal.t()), integer) ::
          BeaconState.t()
  defp update_next_withdrawal_validator_index(state, expected_withdrawals, length_of_validators) do
    length_of_expected_withdrawals = length(expected_withdrawals)

    case length_of_expected_withdrawals == ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD") do
      # Update the next validator index to start the next withdrawal sweep
      true ->
        latest_withdrawal = List.last(expected_withdrawals)
        next_validator_index = rem(latest_withdrawal.validator_index + 1, length_of_validators)
        %BeaconState{state | next_withdrawal_validator_index: next_validator_index}

      # Advance sweep by the max length of the sweep if there was not a full set of withdrawals
      false ->
        next_index =
          state.next_withdrawal_validator_index +
            ChainSpec.get("MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP")

        next_validator_index = rem(next_index, length_of_validators)
        %BeaconState{state | next_withdrawal_validator_index: next_validator_index}
    end
  end

  @spec decrease_balances(BeaconState.t(), list(Withdrawal.t()), list(Withdrawal.t())) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  defp decrease_balances(_state, withdrawals, expected_withdrawals)
       when length(withdrawals) !== length(expected_withdrawals) do
    {:error, "expected withdrawals don't match the state withdrawals in length"}
  end

  @spec decrease_balances(BeaconState.t(), list(Withdrawal.t()), list(Withdrawal.t())) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  defp decrease_balances(state, withdrawals, expected_withdrawals) do
    Enum.zip(expected_withdrawals, withdrawals)
    |> Enum.reduce_while({:ok, state}, &decrease_or_halt/2)
  end

  defp decrease_or_halt({expected_withdrawal, withdrawal}, _)
       when expected_withdrawal !== withdrawal do
    {:halt, {:error, "withdrawal != expected_withdrawal"}}
  end

  defp decrease_or_halt({_, withdrawal}, {:ok, state}) do
    {:cont,
     {:ok, BeaconState.decrease_balance(state, withdrawal.validator_index, withdrawal.amount)}}
  end

  @spec get_expected_withdrawals(BeaconState.t()) :: list(Withdrawal.t())
  defp get_expected_withdrawals(
         %BeaconState{
           next_withdrawal_index: next_withdrawal_index,
           next_withdrawal_validator_index: next_withdrawal_validator_index,
           validators: validators,
           balances: balances
         } = state
       ) do
    # Compute the next batch of withdrawals which should be included in a block.
    epoch = Accessors.get_current_epoch(state)
    withdrawal_index = next_withdrawal_index
    validator_index = next_withdrawal_validator_index
    max_validators_per_withdrawals_sweep = ChainSpec.get("MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP")
    bound = min(length(validators), max_validators_per_withdrawals_sweep)

    {withdrawals, _, _} =
      Enum.reduce_while(0..(bound - 1), {[], validator_index, withdrawal_index}, fn _,
                                                                                    {withdrawals,
                                                                                     validator_index,
                                                                                     withdrawal_index} ->
        validator = Enum.fetch!(validators, validator_index)
        balance = Enum.fetch!(balances, validator_index)
        %Validator{withdrawal_credentials: withdrawal_credentials} = validator

        {withdrawals, withdrawal_index} =
          cond do
            Validator.is_fully_withdrawable_validator(validator, balance, epoch) ->
              <<_::binary-size(12), execution_address::binary>> = withdrawal_credentials

              withdrawal = %Withdrawal{
                index: withdrawal_index,
                validator_index: validator_index,
                address: execution_address,
                amount: balance
              }

              withdrawals = [withdrawal | withdrawals]
              withdrawal_index = withdrawal_index + 1

              {withdrawals, withdrawal_index}

            Validator.is_partially_withdrawable_validator(validator, balance) ->
              <<_::binary-size(12), execution_address::binary>> = withdrawal_credentials
              max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

              withdrawal = %Withdrawal{
                index: withdrawal_index,
                validator_index: validator_index,
                address: execution_address,
                amount: balance - max_effective_balance
              }

              withdrawals = [withdrawal | withdrawals]
              withdrawal_index = withdrawal_index + 1

              {withdrawals, withdrawal_index}

            true ->
              {withdrawals, withdrawal_index}
          end

        max_withdrawals_per_payload = ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD")

        if length(withdrawals) == max_withdrawals_per_payload do
          {:halt, {withdrawals, validator_index, withdrawal_index}}
        else
          validator_index = rem(validator_index + 1, length(validators))
          {:cont, {withdrawals, validator_index, withdrawal_index}}
        end
      end)

    Enum.reverse(withdrawals)
  end
end
