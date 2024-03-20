defmodule LambdaEthereumConsensus.Container do
  @moduledoc """
    Container for SSZ
  """
  alias LambdaEthereumConsensus.SszEx

  @doc """
  Returns a keyword list, where the keys are attribute names, and the values are schemas.
  It specifies both the de/serialization order and the schema for each key in the map.
  """
  @callback schema() :: Keyword.t(SszEx.schema())

  @doc """
  Marks the module as implementing the `Container` behaviour,
  and adds some compile-time callback checks.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour unquote(__MODULE__)

      @after_compile unquote(__MODULE__)
    end
  end

  @doc """
  Called after compilation. Checks if the current module is a valid schema.
  """
  def __after_compile__(env, _bytecode) do
    SszEx.validate_schema!(env.module)
  end
end
