defmodule Constants do
  @moduledoc """
  Constants module with 0-arity functions.
  """

  @spec genesis_epoch() :: integer
  def genesis_epoch, do: 0

  @spec timely_target_flag_index() :: integer
  def timely_target_flag_index, do: 1

  @spec eth1_address_withdrawal_prefix() :: binary
  def eth1_address_withdrawal_prefix, do: <<0x01>>

  @spec far_future_epoch() :: integer
  def far_future_epoch, do: 2 ** 64 - 1
end
