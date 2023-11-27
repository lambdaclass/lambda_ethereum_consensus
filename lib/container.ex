defmodule LambdaEthereumConsensus.Container do
  @moduledoc """
    Container for SSZ
  """

  @doc """
  List of ordered {key, schema} tuples. 
    It specifies both the serialization order and the schema for each key in the map.
  """
  @callback schema() :: [{atom, any}]
end
