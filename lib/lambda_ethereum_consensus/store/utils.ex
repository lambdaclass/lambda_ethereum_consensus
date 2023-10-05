defmodule LambdaEthereumConsensus.Store.Utils do
  @moduledoc """
  This module contains utility functions for interacting with storage.
  """
  @spec get_key(binary, non_neg_integer | binary) :: binary
  def get_key(prefix, suffix) when is_integer(suffix) do
    # NOTE: this uses the last 64 bits of the suffix only
    prefix <> <<suffix::64>>
  end

  def get_key(prefix, suffix) when is_binary(suffix) do
    prefix <> suffix
  end
end
