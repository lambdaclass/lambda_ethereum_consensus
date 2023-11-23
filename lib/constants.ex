defmodule Constants do
  @moduledoc """
  Constants module with 0-arity functions.
  """

  @spec genesis_epoch() :: integer
  def genesis_epoch, do: 0

  @spec bls_withdrawal_prefix() :: <<_::8>>
  def bls_withdrawal_prefix, do: <<0>>

  @spec eth1_address_withdrawal_prefix() :: <<_::8>>
  def eth1_address_withdrawal_prefix, do: <<1>>

  @spec domain_beacon_attester() :: SszTypes.domain_type()
  def domain_beacon_attester, do: <<1, 0, 0, 0>>

  @spec domain_beacon_proposer() :: SszTypes.domain_type()
  def domain_beacon_proposer, do: <<0, 0, 0, 0>>

  @spec domain_randao() :: SszTypes.domain_type()
  def domain_randao, do: <<2, 0, 0, 0>>

  @spec domain_sync_committee() :: SszTypes.domain_type()
  def domain_sync_committee, do: <<7, 0, 0, 0>>

  @spec domain_voluntary_exit() :: SszTypes.domain_type()
  def domain_voluntary_exit, do: <<4, 0, 0, 0>>

  @spec domain_bls_to_execution_change() :: SszTypes.domain_type()
  def domain_bls_to_execution_change, do: <<10, 0, 0, 0>>

  @spec timely_source_flag_index() :: integer
  def timely_source_flag_index, do: 0

  @spec timely_target_flag_index() :: integer
  def timely_target_flag_index, do: 1

  @spec timely_head_flag_index() :: integer
  def timely_head_flag_index, do: 2

  @spec proposer_weight() :: integer
  def proposer_weight, do: 8

  @spec sync_reward_weight() :: integer
  def sync_reward_weight, do: 2

  @spec weight_denominator() :: integer
  def weight_denominator, do: 64

  @spec participation_flag_weights() :: list(integer)
  def participation_flag_weights,
    do: [timely_source_weight(), timely_target_weight(), timely_head_weight()]

  @spec base_reward_factor() :: integer
  def base_reward_factor, do: 64

  @spec timely_source_weight() :: integer
  def timely_source_weight, do: 14

  @spec timely_target_weight() :: integer
  def timely_target_weight, do: 26

  @spec timely_head_weight() :: integer
  def timely_head_weight, do: 14

  @spec far_future_epoch() :: integer
  def far_future_epoch, do: 2 ** 64 - 1

  @spec intervals_per_slot() :: integer
  def intervals_per_slot, do: 3
end
