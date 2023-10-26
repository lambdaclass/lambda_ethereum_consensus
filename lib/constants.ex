defmodule Constants do
  @moduledoc """
  Constants module with 0-arity functions.
  """

  @spec genesis_epoch() :: integer
  def genesis_epoch, do: 0

  @spec timely_target_flag_index() :: integer
  def timely_target_flag_index, do: 1

  @spec min_per_epoch_churn_limit() :: integer
  def min_per_epoch_churn_limit, do: 4

  @spec churn_limit_quotient() :: integer
  def churn_limit_quotient, do: 65536

  @spec max_seed_lookahead() :: integer
  def max_seed_lookahead, do: 4

  @spec far_future_epoch() :: integer
  def far_future_epoch, do: 2 ** 64 - 1

  @spec min_validator_withdrawability_delay() :: integer
  def min_validator_withdrawability_delay, do: 265

  @spec domain_beacon_proposer() :: BitString
  def domain_beacon_proposer, do: <<0, 0, 0, 0>>

  @spec domain_beacon_attester() :: BitString
  def domain_beacon_proposer, do: <<0::4, 1::4, 0::4, 0::4, 0::4, 0::4, 0::4, 0::4>>

  @spec proposer_weight() :: integer
  def proposer_weight, do: 8

  @spec weight_denominator() :: integer
  def weight_denominator, do: 64
end
