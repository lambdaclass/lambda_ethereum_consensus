defmodule LambdaEthereumConsensus.StateTransition.Mutators do
  @moduledoc """
  Functions mutating the current beacon state
  """
  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias Types.BeaconState
  alias Types.Validator

  @doc """
    Increase the validator balance at index ``index`` by ``delta``.
  """
  @spec increase_balance(BeaconState.t(), Types.validator_index(), Types.gwei()) ::
          BeaconState.t()
  def increase_balance(%BeaconState{balances: balances} = state, index, delta) do
    %BeaconState{state | balances: List.update_at(balances, index, &(&1 + delta))}
  end

  @doc """
      Decrease the validator balance at index ``index`` by ``delta``, with underflow protection.
  """
  @spec decrease_balance(BeaconState.t(), Types.validator_index(), Types.gwei()) ::
          BeaconState.t()
  def decrease_balance(%BeaconState{balances: balances} = state, index, delta) do
    %BeaconState{state | balances: List.update_at(balances, index, &max(&1 - delta, 0))}
  end

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
      {:ok, validator}
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

  @doc """
  Slash the validator with index ``slashed_index``.
  """
  @spec slash_validator(
          BeaconState.t(),
          Types.validator_index(),
          Types.validator_index() | nil
        ) ::
          {:ok, BeaconState.t()} | {:error, binary()}
  def slash_validator(state, slashed_index, whistleblower_index \\ nil) do
    epoch = Accessors.get_current_epoch(state)

    case initiate_validator_exit(state, slashed_index) do
      {:error, msg} ->
        {:error, msg}

      {:ok, validator} ->
        validator = %Validator{
          validator
          | slashed: true,
            withdrawable_epoch:
              max(
                validator.withdrawable_epoch,
                epoch + ChainSpec.get("EPOCHS_PER_SLASHINGS_VECTOR")
              )
        }

        state = %BeaconState{
          state
          | validators: List.replace_at(state.validators, slashed_index, validator),
            slashings:
              List.replace_at(
                state.slashings,
                rem(epoch, ChainSpec.get("EPOCHS_PER_SLASHINGS_VECTOR")),
                Enum.at(state.slashings, rem(epoch, ChainSpec.get("EPOCHS_PER_SLASHINGS_VECTOR"))) +
                  validator.effective_balance
              )
        }

        slashing_penalty =
          div(
            validator.effective_balance,
            ChainSpec.get("MIN_SLASHING_PENALTY_QUOTIENT_BELLATRIX")
          )

        proposer_index = Accessors.get_beacon_proposer_index(state)

        case proposer_index do
          {:error, msg} ->
            {:error, msg}

          {:ok, proposer_index} ->
            whistleblower_index = whistleblower_index(whistleblower_index, proposer_index)

            whistleblower_reward =
              div(validator.effective_balance, ChainSpec.get("WHISTLEBLOWER_REWARD_QUOTIENT"))

            proposer_reward =
              (whistleblower_reward * Constants.proposer_weight())
              |> div(Constants.weight_denominator())

            # Decrease slashers balance, apply proposer and whistleblower rewards
            {:ok,
             state
             |> decrease_balance(slashed_index, slashing_penalty)
             |> increase_balance(proposer_index, proposer_reward)
             |> increase_balance(whistleblower_index, whistleblower_reward - proposer_reward)}
        end
    end
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
        {:ok, increase_balance(state, index, amount)}

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

  defp apply_initial_deposit(state, pubkey, withdrawal_credentials, amount) do
    {:ok,
     %BeaconState{
       state
       | validators:
           state.validators ++
             [
               Types.Deposit.get_validator_from_deposit(
                 pubkey,
                 withdrawal_credentials,
                 amount
               )
             ],
         balances: state.balances ++ [amount],
         previous_epoch_participation: state.previous_epoch_participation ++ [0],
         current_epoch_participation: state.current_epoch_participation ++ [0],
         inactivity_scores: state.inactivity_scores ++ [0]
     }}
  end
end
