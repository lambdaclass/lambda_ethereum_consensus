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
end
