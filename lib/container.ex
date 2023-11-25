defmodule LambdaEthereumConsensus.Container do
  @moduledoc """
    Container for SSZ
  """

  @doc """
  List of ordered key/value schemas of struct fields
  """
  @callback schema() :: [tuple]
end
