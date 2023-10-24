defmodule LambdaEthereumConsensus.StateTransition.Operations do
  @moduledoc """
  State transition Operations related functions
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias LambdaEthereumConsensus.StateTransition.Mutators
  alias SszTypes.BeaconState
  alias SszTypes.ExecutionPayload
  alias SszTypes.Withdrawal
  alias SszTypes.Validator

  @spec process_withdrawals(BeaconState.t(), ExecutionPayload.t()) ::
          {:error, String.t()}
  def process_withdrawals(state, %ExecutionPayload{withdrawals: withdrawals}) do
    if length(withdrawals) !== length(get_expected_withdrawals(state)) do
      {:error, "length of withdrawals is not equal to expected withdrawals"}
    end
  end

  @spec process_withdrawals(BeaconState.t(), ExecutionPayload.t()) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def process_withdrawals(state, %ExecutionPayload{withdrawals: withdrawals} = payload) do
    expected_withdrawals = get_expected_withdrawals(state)

    result =
      Enum.reduce_while(Enum.zip(expected_withdrawals, withdrawals), {:ok, state}, fn element,
                                                                                      {_, state} ->
        expected_withdrawal = Enum.fetch!(element, 0)
        withdrawal = Enum.fetch!(element, 1)

        %Withdrawal{validator_index: validator_index, amount: amount} = withdrawal

        if withdrawal !== expected_withdrawal do
          {:halt, {:error, "withdrawal != expected_withdrawal"}}
        else
          new_state = Mutators.decrease_balance(state, validator_index, amount)
          {:cont, {:ok, new_state}}
        end
      end)

    response =
      case result do
        {:ok, state} ->
          # Update the next withdrawal index if this block contained withdrawals
          new_state =
            if length(expected_withdrawals) !== 0 do
              latest_withdrawal = List.last(expected_withdrawals)
              %Withdrawal{index: index} = latest_withdrawal
              new_state = %BeaconState{state | next_withdrawal_index: index + 1}
              new_state
            end

          max_withdrawals_per_payload = ChainSpec.get("MAX_WITHDRAWALS_PER_PAYLOAD")
          %BeaconState{validators: validators} = new_state

          # Update the next validator index to start the next withdrawal sweep
          new_state =
            if length(expected_withdrawals) == max_withdrawals_per_payload do
              # Next sweep starts after the latest withdrawal's validator index
              latest_withdrawal = List.last(expected_withdrawals)
              %Withdrawal{validator_index: validator_index} = latest_withdrawal
              next_validator_index = rem(validator_index + 1, length(validators))

              new_state = %BeaconState{
                new_state
                | next_withdrawal_validator_index: next_validator_index
              }

              new_state
            else
              # Advance sweep by the max length of the sweep if there was not a full set of withdrawals
              max_validators_per_withdrawals_sweep =
                ChainSpec.get("MAX_VALIDATORS_PER_WITHDRAWALS_SWEEP")

              %BeaconState{next_withdrawal_validator_index: next_withdrawal_validator_index} =
                new_state

              next_index = next_withdrawal_validator_index + max_validators_per_withdrawals_sweep
              next_validator_index = rem(next_index, length(validators))

              new_state = %BeaconState{
                new_state
                | next_withdrawal_validator_index: next_validator_index
              }

              new_state
            end

        {:error, reason} ->
          {:error, reason}
      end

    response
  end

  @spec get_expected_withdrawals(BeaconState.t()) :: list[Withdrawal.t()]
  defp get_expected_withdrawals(
         %BeaconState{
           next_withdrawal_index: next_withdrawal_index,
           next_withdrawal_validator_index: next_withdrawal_validator_index,
           validators: validators,
           balances: balances
         } = state
       ) do
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
        balance = Enum.fetch!(balances, withdrawal_index)
        %Validator{withdrawal_credentials: withdrawal_credentials} = validator

        {withdrawals, withdrawal_index} =
          cond do
            Predicates.is_fully_withdrawable_validator(validator, balance, epoch) ->
              <<_::binary-size(12), execution_address::binary>> = withdrawal_credentials

              withdrawal = %Withdrawal{
                index: withdrawal_index,
                validator_index: validator_index,
                address: execution_address,
                amount: balance
              }

              withdrawals = List.insert_at(withdrawals, 0, withdrawal)
              withdrawal_index = withdrawal_index + 1

              {withdrawals, withdrawal_index}

            Predicates.is_partially_withdrawable_validator(validator, balance) ->
              <<_::binary-size(12), execution_address::binary>> = withdrawal_credentials
              max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

              withdrawal = %Withdrawal{
                index: withdrawal_index,
                validator_index: validator_index,
                address: execution_address,
                amount: balance - max_effective_balance
              }

              withdrawals = List.insert_at(withdrawals, 0, withdrawal)
              withdrawal_index = withdrawal_index + 1

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
