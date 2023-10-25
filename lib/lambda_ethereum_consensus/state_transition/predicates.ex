defmodule LambdaEthereumConsensus.StateTransition.Predicates do
  @moduledoc """
  Range of predicates enabling verification of state
  """

  alias LambdaEthereumConsensus.StateTransition.Accessors
  alias SszTypes.BeaconState
  alias SszTypes.Validator
  import Bitwise

  # @default_execution_payload_header %ExecutionPayloadHeader{
  #   parent_hash: SszTypes.hash32(),
  #   fee_recipient: SszTypes.execution_address(),
  #   state_root: SszTypes.root(),
  #   receipts_root: SszTypes.root(),
  #   logs_bloom: binary(),
  #   prev_randao: SszTypes.bytes32(),
  #   block_number: 0,
  #   gas_limit: 0,
  #   gas_used: 0,
  #   timestamp: 0,
  #   extra_data: binary(),
  #   base_fee_per_gas: 0,
  #   block_hash: SszTypes.hash32(),
  #   transactions_root: SszTypes.root(),
  #   withdrawals_root: SszTypes.root()
  # }

  @doc """
  Checks if state is pre or post merge
  """
  @spec is_merge_transition_complete(SszTypes.BeaconState.t()) :: boolean()
  def is_merge_transition_complete(state) do
    state.latest_execution_payload_header != SszTypes.ExecutionPayloadHeader
  end

  @doc """
  Check if ``validator`` is active.
  """
  @spec is_active_validator(Validator.t(), SszTypes.epoch()) :: boolean
  def is_active_validator(
        %Validator{activation_epoch: activation_epoch, exit_epoch: exit_epoch},
        epoch
      ) do
    activation_epoch <= epoch && epoch < exit_epoch
  end

  @doc """
  Check if ``validator`` is eligible to be placed into the activation queue.
  """
  @spec is_eligible_for_activation_queue(Validator.t()) :: boolean
  def is_eligible_for_activation_queue(%Validator{} = validator) do
    far_future_epoch = Constants.far_future_epoch()
    max_effective_balance = ChainSpec.get("MAX_EFFECTIVE_BALANCE")

    validator.activation_eligibility_epoch == far_future_epoch &&
      validator.effective_balance == max_effective_balance
  end

  @doc """
  Check if ``validator`` is eligible for activation.
  """
  @spec is_eligible_for_activation(BeaconState.t(), Validator.t()) :: boolean
  def is_eligible_for_activation(%BeaconState{} = state, %Validator{} = validator) do
    far_future_epoch = Constants.far_future_epoch()

    validator.activation_eligibility_epoch <= state.finalized_checkpoint.epoch &&
      validator.activation_epoch == far_future_epoch
  end

  @doc """
  If the beacon chain has not managed to finalise a checkpoint for MIN_EPOCHS_TO_INACTIVITY_PENALTY epochs 
  (that is, four epochs), then the chain enters the inactivity leak.
  """
  @spec is_in_inactivity_leak(BeaconState.t()) :: boolean
  def is_in_inactivity_leak(%BeaconState{} = state) do
    min_epochs_to_inactivity_penalty = ChainSpec.get("MIN_EPOCHS_TO_INACTIVITY_PENALTY")
    Accessors.get_finality_delay(state) > min_epochs_to_inactivity_penalty
  end

  @doc """
  Return whether ``flags`` has ``flag_index`` set.
  """
  @spec has_flag(SszTypes.participation_flags(), integer) :: boolean
  def has_flag(participation_flags, flag_index) do
    flag = 2 ** flag_index
    (participation_flags &&& flag) === flag
  end
end
