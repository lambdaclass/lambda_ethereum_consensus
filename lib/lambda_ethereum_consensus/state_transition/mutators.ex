defmodule LambdaEthereumConsensus.StateTransition.Mutators do
  @moduledoc """
  Functions mutating the current beacon state
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.BeaconState
  alias Types.Validator

  @doc """
  Initiate the exit of the validator with index ``index``.
  """
  @spec initiate_validator_exit(BeaconState.t(), integer()) ::
          {:ok, Validator.t()} | {:error, String.t()}
  def initiate_validator_exit(%BeaconState{} = state, index) when is_integer(index) do
    initiate_validator_exit(state, Aja.Vector.at!(state.validators, index))
  end

  @spec initiate_validator_exit(BeaconState.t(), Validator.t()) ::
          {:ok, Validator.t()} | {:error, String.t()}
  def initiate_validator_exit(%BeaconState{} = state, %Validator{} = validator) do
    far_future_epoch = Constants.far_future_epoch()
    min_validator_withdrawability_delay = ChainSpec.get("MIN_VALIDATOR_WITHDRAWABILITY_DELAY")

    if validator.exit_epoch != far_future_epoch do
      {:ok, validator}
    else
      exit_epochs =
        state.validators
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
        state.validators
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

      if next_withdrawable_epoch > Constants.far_future_epoch() do
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

  @doc """
  Slash the validator with index ``slashed_index``.
  """
  @spec slash_validator(
          BeaconState.t(),
          Types.validator_index(),
          Types.validator_index() | nil
        ) ::
          {:ok, BeaconState.t()} | {:error, String.t()}
  def slash_validator(state, slashed_index, whistleblower_index \\ nil) do
    with {:ok, validator} <- initiate_validator_exit(state, slashed_index),
         state = add_slashing(state, validator, slashed_index),
         {:ok, proposer_index} <- Accessors.get_beacon_proposer_index(state) do
      slashing_penalty =
        validator.effective_balance
        |> div(ChainSpec.get("MIN_SLASHING_PENALTY_QUOTIENT_BELLATRIX"))

      whistleblower_index = whistleblower_index(whistleblower_index, proposer_index)

      whistleblower_reward =
        div(validator.effective_balance, ChainSpec.get("WHISTLEBLOWER_REWARD_QUOTIENT"))

      proposer_reward =
        (whistleblower_reward * Constants.proposer_weight())
        |> div(Constants.weight_denominator())

      # Decrease slashers balance, apply proposer and whistleblower rewards
      {:ok,
       state
       |> BeaconState.decrease_balance(slashed_index, slashing_penalty)
       |> BeaconState.increase_balance(proposer_index, proposer_reward)
       |> BeaconState.increase_balance(
         whistleblower_index,
         whistleblower_reward - proposer_reward
       )}
    end
  end

  defp add_slashing(state, validator, slashed_index) do
    epoch = Accessors.get_current_epoch(state)
    epochs_per_slashings_vector = ChainSpec.get("EPOCHS_PER_SLASHINGS_VECTOR")

    v =
      Enum.at(state.slashings, rem(epoch, epochs_per_slashings_vector)) +
        validator.effective_balance

    new_slashings =
      List.replace_at(
        state.slashings,
        rem(epoch, epochs_per_slashings_vector),
        v
      )

    %Validator{
      validator
      | slashed: true,
        withdrawable_epoch:
          validator.withdrawable_epoch
          |> max(epoch + epochs_per_slashings_vector)
    }
    |> then(
      &%BeaconState{
        state
        | validators: Aja.Vector.replace_at!(state.validators, slashed_index, &1),
          slashings: new_slashings
      }
    )
  end

  defp whistleblower_index(whistleblower_index, proposer_index) do
    if whistleblower_index == nil, do: proposer_index, else: whistleblower_index
  end

  @spec apply_deposit(
          BeaconState.t(),
          Types.bls_pubkey(),
          Types.bytes32(),
          Types.uint64(),
          Types.bls_signature()
        ) :: {:ok, BeaconState.t()} | {:error, binary()}
  def apply_deposit(state, pubkey, withdrawal_credentials, amount, signature) do
    case Enum.find_index(state.validators, fn validator -> validator.pubkey == pubkey end) do
      index when is_number(index) ->
        {:ok, BeaconState.increase_balance(state, index, amount)}

      _ ->
        deposit_message = %Types.DepositMessage{
          pubkey: pubkey,
          withdrawal_credentials: withdrawal_credentials,
          amount: amount
        }

        domain = Misc.compute_domain(Constants.domain_deposit())

        signing_root = Misc.compute_signing_root(deposit_message, domain)

        if Bls.valid?(pubkey, signing_root, signature) do
          apply_initial_deposit(state, pubkey, withdrawal_credentials, amount)
        else
          {:ok, state}
        end
    end
  end

  defp apply_initial_deposit(%BeaconState{} = state, pubkey, withdrawal_credentials, amount) do
    Types.Deposit.get_validator_from_deposit(pubkey, withdrawal_credentials, amount)
    |> then(&Aja.Vector.append(state.validators, &1))
    |> then(
      &%BeaconState{
        state
        | validators: &1,
          balances: Aja.Vector.append(state.balances, amount),
          previous_epoch_participation: Aja.Vector.append(state.previous_epoch_participation, 0),
          current_epoch_participation: Aja.Vector.append(state.current_epoch_participation, 0),
          inactivity_scores: state.inactivity_scores ++ [0]
      }
    )
    |> then(&{:ok, &1})
  end
end
