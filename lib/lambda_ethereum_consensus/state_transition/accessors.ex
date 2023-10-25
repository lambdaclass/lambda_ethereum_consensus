defmodule LambdaEthereumConsensus.StateTransition.Accessors do
  @moduledoc """
  Functions accessing the current beacon state
  """
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState

  @doc """
  Return the sequence of active validator indices at ``epoch``.
  """
  @spec get_active_validator_indices(BeaconState.t(), SszTypes.epoch()) ::
          list(SszTypes.validator_index())
  def get_active_validator_indices(%BeaconState{validators: validators} = _state, epoch) do
    validators
    |> Stream.with_index()
    |> Stream.filter(fn {v, _} ->
      Predicates.is_active_validator(v, epoch)
    end)
    |> Stream.map(fn {_, index} -> index end)
    |> Enum.to_list()
  end

  @doc """
  Return the current epoch.
  """
  @spec get_current_epoch(BeaconState.t()) :: SszTypes.epoch()
  def get_current_epoch(%BeaconState{slot: slot} = _state) do
    Misc.compute_epoch_at_slot(slot)
  end

  @doc """
  Return the previous epoch (unless the current epoch is ``GENESIS_EPOCH``).
  """
  @spec get_previous_epoch(BeaconState.t()) :: SszTypes.epoch()
  def get_previous_epoch(%BeaconState{} = state) do
    current_epoch = get_current_epoch(state)
    genesis_epoch = Constants.genesis_epoch()

    if current_epoch == genesis_epoch do
      genesis_epoch
    else
      current_epoch - 1
    end
  end

  @doc """
  Return the set of validator indices that are both active and unslashed for the given ``flag_index`` and ``epoch``.
  """
  @spec get_unslashed_participating_indices(BeaconState.t(), integer, SszTypes.epoch()) ::
          {:ok, MapSet.t()} | {:error, binary()}
  def get_unslashed_participating_indices(%BeaconState{} = state, flag_index, epoch) do
    if epoch in [get_previous_epoch(state), get_current_epoch(state)] do
      epoch_participation =
        if epoch == get_current_epoch(state) do
          state.current_epoch_participation
        else
          state.previous_epoch_participation
        end

      active_validator_indices = get_active_validator_indices(state, epoch)

      participating_indices =
        active_validator_indices
        |> Stream.filter(fn index ->
          current_epoch_participation = Enum.at(epoch_participation, index)
          Predicates.has_flag(current_epoch_participation, flag_index)
        end)
        |> Stream.filter(fn index ->
          validator = Enum.at(state.validators, index)
          not validator.slashed
        end)

      {:ok, MapSet.new(participating_indices)}
    else
      {:error, "epoch is not present in get_current_epoch or get_previous_epoch of the state"}
    end
  end

  @doc """
  Return the randao mix at a recent ``epoch``.
  """
  @spec get_randao_mix(BeaconState.t(), SszTypes.epoch()) :: SszTypes.bytes32()
  def get_randao_mix(%BeaconState{randao_mixes: randao_mixes}, epoch) do
    epochs_per_historical_vector = ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")
    Enum.fetch!(randao_mixes, rem(epoch, epochs_per_historical_vector))
  end

  @doc """
  Return the validator churn limit for the current epoch.
  """
  @spec get_validator_churn_limit(BeaconState.t()) :: SszTypes.uint64()
  def get_validator_churn_limit(%BeaconState{} = state) do
    active_validator_indices = get_active_validator_indices(state, get_current_epoch(state))
    min_per_epoch_churn_limit = ChainSpec.get("MIN_PER_EPOCH_CHURN_LIMIT")
    churn_limit_quotient = ChainSpec.get("CHURN_LIMIT_QUOTIENT")
    max(min_per_epoch_churn_limit, div(length(active_validator_indices), churn_limit_quotient))
  end

  @doc """
  Returns the number of epochs since the last finalised checkpoint (minus one).
  """
  @spec get_finality_delay(BeaconState.t()) :: SszTypes.uint64()
  def get_finality_delay(%BeaconState{} = state) do
    get_previous_epoch(state) - state.finalized_checkpoint.epoch
  end

  @doc """
  These are the validators that were subject to rewards and penalties in the previous epoch.
  """
  @spec get_eligible_validator_indices(BeaconState.t()) :: list(SszTypes.validator_index())
  def get_eligible_validator_indices(%BeaconState{validators: validators} = state) do
    previous_epoch = get_previous_epoch(state)

    validators
    |> Stream.with_index()
    |> Stream.filter(fn {validator, _index} ->
      Predicates.is_active_validator(validator, previous_epoch) ||
        (validator.slashed && previous_epoch + 1 < validator.withdrawable_epoch)
    end)
    |> Stream.map(fn {_validator, index} -> index end)
    |> Enum.to_list()
  end
end
