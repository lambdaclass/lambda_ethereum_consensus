defmodule Constants do
  @moduledoc """
  Constants module with 0-arity functions.
  The following values are (non-configurable) constants used throughout the specification.
  """

  ### Misc

  @spec genesis_epoch() :: SszTypes.slot()
  def genesis_epoch, do: 0

  @spec genesis_slot() :: SszTypes.slot()
  def genesis_slot, do: 0

  @far_future_epoch 2 ** 64 - 1

  @spec far_future_epoch() :: non_neg_integer()
  def far_future_epoch, do: @far_future_epoch

  @spec base_rewards_per_epoch() :: non_neg_integer()
  def base_rewards_per_epoch, do: 4

  @spec deposit_contract_tree_depth() :: non_neg_integer()
  def deposit_contract_tree_depth, do: 32

  @spec justification_bits_length() :: non_neg_integer()
  def justification_bits_length, do: 4

  @spec endianness() :: atom()
  def endianness, do: :little

  @spec participation_flag_weights() :: list(non_neg_integer())
  def participation_flag_weights,
    do: [timely_source_weight(), timely_target_weight(), timely_head_weight()]

  ### Withdrawal prefixes

  @spec bls_withdrawal_prefix() :: SszTypes.bytes1()
  def bls_withdrawal_prefix, do: <<0>>

  @spec eth1_address_withdrawal_prefix() :: SszTypes.bytes1()
  def eth1_address_withdrawal_prefix, do: <<1>>

  ### Domain types

  @spec domain_beacon_proposer() :: SszTypes.domain_type()
  def domain_beacon_proposer, do: <<0, 0, 0, 0>>

  @spec domain_beacon_attester() :: SszTypes.domain_type()
  def domain_beacon_attester, do: <<1, 0, 0, 0>>

  @spec domain_randao() :: SszTypes.domain_type()
  def domain_randao, do: <<2, 0, 0, 0>>

  @spec domain_deposit() :: SszTypes.domain_type()
  def domain_deposit, do: <<3, 0, 0, 0>>

  @spec domain_voluntary_exit() :: SszTypes.domain_type()
  def domain_voluntary_exit, do: <<4, 0, 0, 0>>

  @spec domain_selection_proof() :: SszTypes.domain_type()
  def domain_selection_proof, do: <<5, 0, 0, 0>>

  @spec domain_aggregate_and_proof() :: SszTypes.domain_type()
  def domain_aggregate_and_proof, do: <<6, 0, 0, 0>>

  @spec domain_application_mask() :: SszTypes.domain_type()
  def domain_application_mask, do: <<0, 0, 0, 1>>

  @spec domain_sync_committee() :: SszTypes.domain_type()
  def domain_sync_committee, do: <<7, 0, 0, 0>>

  @spec domain_sync_committee_selection_proof() :: SszTypes.domain_type()
  def domain_sync_committee_selection_proof, do: <<8, 0, 0, 0>>

  @spec domain_contribution_and_proof() :: SszTypes.domain_type()
  def domain_contribution_and_proof, do: <<9, 0, 0, 0>>

  @spec domain_bls_to_execution_change() :: SszTypes.domain_type()
  def domain_bls_to_execution_change, do: <<10, 0, 0, 0>>

  ### Participation flag indices

  @spec timely_source_flag_index() :: non_neg_integer()
  def timely_source_flag_index, do: 0

  @spec timely_target_flag_index() :: non_neg_integer()
  def timely_target_flag_index, do: 1

  @spec timely_head_flag_index() :: non_neg_integer()
  def timely_head_flag_index, do: 2

  ### Incentivization weights

  @spec timely_source_weight() :: non_neg_integer()
  def timely_source_weight, do: 14

  @spec timely_target_weight() :: non_neg_integer()
  def timely_target_weight, do: 26

  @spec timely_head_weight() :: non_neg_integer()
  def timely_head_weight, do: 14

  @spec sync_reward_weight() :: non_neg_integer()
  def sync_reward_weight, do: 2

  @spec proposer_weight() :: non_neg_integer()
  def proposer_weight, do: 8

  @spec weight_denominator() :: non_neg_integer()
  def weight_denominator, do: 64

  ## Fork choice

  @spec intervals_per_slot() :: non_neg_integer()
  def intervals_per_slot, do: 3

  @spec proposer_score_boost() :: non_neg_integer()
  def proposer_score_boost, do: 3
end
