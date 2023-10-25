defmodule Constants do
  @moduledoc """
  Constants module with 0-arity functions.
  """

  @spec genesis_epoch() :: integer
  def genesis_epoch, do: 0

  @spec genesis_slot() :: integer
  def genesis_slot, do: 0

  @spec timely_target_flag_index() :: integer
  def timely_target_flag_index, do: 1

  @spec far_future_epoch() :: integer
  def far_future_epoch, do: 2 ** 64 - 1
end
