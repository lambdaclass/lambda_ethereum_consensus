defmodule LambdaEthereumConsensus.StateTransition.Accessors do
  @moduledoc """
  Functions accessing the current beacon state
  """

  alias ChainSpec
  alias LambdaEthereumConsensus.StateTransition.Misc
  alias LambdaEthereumConsensus.StateTransition.Predicates
  alias SszTypes.BeaconState

  @doc """
  Return the current epoch.
  """
  @spec get_current_epoch(BeaconState.t()) :: SszTypes.epoch()
  def get_current_epoch(%BeaconState{slot: slot} = _state) do
    Misc.compute_epoch_at_slot(slot)
  end

  @doc """
  Return the randao mix at a recent ``epoch``.
  """
  @spec get_randao_mix(BeaconState.t(), SszTypes.epoch()) :: SszTypes.bytes32()
  def get_randao_mix(%BeaconState{randao_mixes: randao_mixes}, epoch) do
    epochs_per_historical_vector = ChainSpec.get("EPOCHS_PER_HISTORICAL_VECTOR")
    Enum.fetch!(randao_mixes, rem(epoch, epochs_per_historical_vector))
  end

  @spec get_active_validator_indices(BeaconState.t(), SszTypes.epoch()) :: list[integer]
  def get_active_validator_indices(%BeaconState{validators: validators}, epoch) do
    validators_indices = Enum.with_index(validators)

    active_indices =
      for {validator, index} <- validators_indices,
          Predicates.is_active_validator(validator, epoch) do
        index
      end

    active_indices
  end

  @spec get_total_balance(BeaconState.t(), list[integer]) :: SszTypes.gwei()
  def get_total_balance(%BeaconState{validators: validators}, indices) do
    effective_balance_increment = ChainSpec.get("EFFECTIVE_BALANCE_INCREMENT")
    sum = Enum.reduce(indices, 0, fn index, acc ->
      acc + Enum.at(validators, index).effective_balance
    end)

    max(effective_balance_increment, sum)
  end

  @spec get_total_active_balance(BeaconState.t()) :: SszTypes.gwei()
  def get_total_active_balance(state) do
    active_validator_indices = get_active_validator_indices(state, get_current_epoch(state))
    get_total_balance(state, Enum.uniq(active_validator_indices))
  end
end
