defmodule LambdaEthereumConsensus.Container do
  @moduledoc """
    Container for SSZ
  """
  alias LambdaEthereumConsensus.SszEx

  @doc """
  List of ordered {key, schema} tuples.
    It specifies both the serialization order and the schema for each key in the map.
  """
  @callback schema() :: Keyword.t(SszEx.schema())
end
