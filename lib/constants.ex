defmodule Constants do
  @moduledoc """
  Constants module with 0-arity functions.
  """

  @spec genesis_epoch() :: integer
  def genesis_epoch, do: 0

  @spec domain_beacon_attester() :: <<_::32>>
  def domain_beacon_attester, do: <<1, 0, 0, 0>>
  
  @spec domain_beacon_proposer() :: <<_::32>>
  def domain_beacon_proposer, do: <<0, 0, 0, 0>>

  @spec timely_source_flag_index() :: integer
  def timely_source_flag_index, do: 0

  @spec timely_target_flag_index() :: integer
  def timely_target_flag_index, do: 1

  @spec timely_head_flag_index() :: integer
  def timely_head_flag_index, do: 2

  @spec proposer_weight() :: integer
  def proposer_weight, do: 8

  @spec weight_denominator() :: integer
  def weight_denominator, do: 64

  @spec participation_flag_weights() :: list(integer)
  def participation_flag_weights, do: [0, 1, 2]

  @spec base_reward_factor() :: integer
  def base_reward_factor, do: 64
end
