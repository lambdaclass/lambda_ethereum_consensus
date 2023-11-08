defmodule LambdaEthereumConsensus.Utils do
  @moduledoc """
  Set of utility functions used throughout the project.
  """

  @doc """
  If ``condition`` is true, run ``fun`` on ``value`` and return the result.
  Else return the unmodified ``value``.
  """
  @spec if_then_update(any(), boolean(), (any() -> any())) :: any()
  def if_then_update(value, true, fun), do: fun.(value)
  def if_then_update(value, false, _fun), do: value

  @doc """
  If first arg is an ``{:ok, value}`` tuple, apply ``fun`` to ``value`` and
  return the result. Else, if it's an ``{:error, _}`` tuple, returns it.
  """
  @spec map({:ok | :error, any()}, (any() -> any())) :: any() | {:error, any()}
  def map({:ok, value}, fun), do: fun.(value)
  def map({:error, _} = err, _fun), do: err
end
