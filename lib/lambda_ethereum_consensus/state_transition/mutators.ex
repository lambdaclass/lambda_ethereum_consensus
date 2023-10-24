defmodule LambdaEthereumConsensus.StateTransition.Mutators do

  alias SszTypes.BeaconState

  @doc """
    Decrease the validator balance at index ``index`` by ``delta``, with underflow protection.
  """
  @spec decrease_balance(BeaconState.t(), SszTypes.validator_index(), SszTypes.gwei()) ::
          BeaconState.t()
  def decrease_balance(%BeaconState{balances: balances} = state, index, delta) do
    new_state =
      if delta > Enum.fetch!(balances, index) do
        %BeaconState{state | balances: List.replace_at(balances, index, 0)}
      else
        %BeaconState{
          state
          | balances: List.replace_at(balances, index, Enum.fetch!(balances, index) - delta)
        }
      end

    new_state

  @moduledoc """
  Functions mutating the current beacon state
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias SszTypes.BeaconState
  alias SszTypes.Validator

  @doc """
  Initiate the exit of the validator with index ``index``.
  """
  @spec initiate_validator_exit(BeaconState.t(), integer) ::
          {:ok, Validator.t()} | {:error, binary()}
  def initiate_validator_exit(%BeaconState{validators: validators} = state, index) do
    validator = Enum.at(validators, index)
    far_future_epoch = Constants.far_future_epoch()
    min_validator_withdrawability_delay = ChainSpec.get("MIN_VALIDATOR_WITHDRAWABILITY_DELAY")

    if validator.exit_epoch != far_future_epoch do
      validator
    else
      exit_epochs =
        validators
        |> Stream.filter(fn validator ->
          validator.exit_epoch != far_future_epoch
        end)
        |> Stream.map(fn validator -> validator.exit_epoch end)
        |> Enum.to_list()

      exit_queue_epoch =
        Enum.max(
          exit_epochs ++ [Misc.compute_activation_exit_epoch(Accessors.get_current_epoch(state))]
        )

      exit_queue_churn =
        validators
        |> Stream.filter(fn validator ->
          validator.exit_epoch == exit_queue_epoch
        end)
        |> Enum.to_list()
        |> length()

      exit_queue_epoch =
        if exit_queue_churn >= Accessors.get_validator_churn_limit(state) do
          exit_queue_epoch + 1
        else
          exit_queue_epoch
        end

      next_withdrawable_epoch = exit_queue_epoch + min_validator_withdrawability_delay

      if next_withdrawable_epoch > 2 ** 64 - 1 do
        {:error, "withdrawable_epoch_too_large"}
      else
        {:ok,
         %{
           validator
           | exit_epoch: exit_queue_epoch,
             withdrawable_epoch: next_withdrawable_epoch
         }}
      end
    end

  end
end
